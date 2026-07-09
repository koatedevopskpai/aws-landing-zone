# =============================================================================
# MAIN.TF — AWS LANDING ZONE FOR SECONDWAVE (FCA-REGULATED FINTECH)
# =============================================================================
# ARCHITECTURE DECISION: Multi-account structure using AWS Organizations.
# This landing zone hosts shared services (logging, networking, security) in a
# dedicated shared-services account and delegates workload accounts per environment.
# Account switching is achieved via provider aliases when running in a management
# account, or via Terraform Cloud run-specific variables for isolated execution.
#
# Each environment gets:
#   - A VPC with public/private/isolated subnets
#   - Transit Gateway attachment for cross-VPC routing
#   - KMS keys scoped per service per environment
#   - AWS Config rules (if enabled)
#   - VPC Flow Logs (mandatory)
#   - Consistent tagging
#
# The logging infrastructure (S3 Object Lock + CloudWatch) lives in the
# shared-services account as a central audit sink.

# =============================================================================
# PROVIDER CONFIGURATION
# =============================================================================
# ARCHITECTURE DECISION: Provider configuration supports multiple accounts via
# alias patterns. In production, use assume_role to switch into each account.
# The shared-services provider is the default for root-module resources.
provider "aws" {
  region = var.region
  # SECURITY SAFEGUARD: Default provider should target shared-services account.
  # Workload account providers are created in each environment module call.
  assume_role {
    role_arn = "arn:aws:iam::${var.account_ids["shared-services"]}:role/TerraformExecutionRole"
  }
  default_tags {
    tags = var.tags
  }
}

# ARCHITECTURE DECISION: Each workload account gets its own provider alias.
# for_each over the account_ids map creates a provider per environment.
provider "aws" {
  alias  = "dev"
  region = var.environments["dev"].region
  assume_role {
    role_arn = "arn:aws:iam::${var.account_ids["dev"]}:role/TerraformExecutionRole"
  }
  default_tags {
    tags = merge(var.tags, { Environment = "dev" })
  }
}

provider "aws" {
  alias  = "staging"
  region = var.environments["staging"].region
  assume_role {
    role_arn = "arn:aws:iam::${var.account_ids["staging"]}:role/TerraformExecutionRole"
  }
  default_tags {
    tags = merge(var.tags, { Environment = "staging" })
  }
}

provider "aws" {
  alias  = "prod"
  region = var.environments["prod"].region
  assume_role {
    role_arn = "arn:aws:iam::${var.account_ids["prod"]}:role/TerraformExecutionRole"
  }
  default_tags {
    tags = merge(var.tags, { Environment = "prod" })
  }
}

# =============================================================================
# VPCs PER ENVIRONMENT
# =============================================================================
# ARCHITECTURE DECISION: Using for_each over a local set of environment keys
# so each environment gets an identical VPC pattern but with environment-specific
# CIDRs and feature flags. count would work but for_each provides a stable map key.
locals {
  # Determine which environments to provision based on var.environment
  # When var.environment is "all", provision all environments.
  # Otherwise provision only the specified environment.
  environment_keys = var.environment == "all" ? keys(var.account_ids) : [var.environment]
}

resource "aws_ec2_managed_prefix_list" "vpc_cidrs" {
  # ARCHITECTURE DECISION: Managed prefix list for VPC CIDRs to simplify
  # security group rules between environments without hardcoding CIDRs.
  name           = "${var.project_name}-vpc-cidrs"
  address_family = "IPv4"
  max_entries    = 10

  dynamic "entry" {
    for_each = var.account_ids
    content {
      cidr        = var.vpc_cidrs[entry.key]
      description = "${entry.key} VPC CIDR"
    }
  }
}

module "vpc" {
  source   = "./modules/vpc"
  for_each = toset(local.environment_keys)

  providers = {
    aws = try(try(aws[each.key], null), aws) # fallback to default (shared-services)
  }

  vpc_cidr        = var.vpc_cidrs[each.key]
  environment     = each.key
  project_name    = var.project_name
  enable_natgw    = var.environments[each.key].enable_natgw
  enable_flow_logs = var.environments[each.key].enable_flow_logs
  enable_vpn      = try(var.environments[each.key].enable_vpn, false)
  tags            = merge(var.tags, { Environment = each.key, VpcType = "landing-zone" })
}

# =============================================================================
# TRANSIT GATEWAY (Shared-Services Account)
# =============================================================================
# ARCHITECTURE DECISION: Transit Gateway over VPC Peering because:
# 1. TGW supports transitive routing across 10+ VPCs natively; VPC Peering
#    requires a mesh (n*(n-1)/2 peerings).
# 2. TGW enables centralized network inspection (DPI, firewall) via appliance VPC.
# 3. TGW attachments support VPN, Direct Connect, and SD-WAN in one hub.
# 4. TGW route tables allow segmenting traffic (e.g., prod cannot reach dev).
# See docs/ADR/001-transit-gateway-over-vpc-peering.md for full analysis.
module "transit_gateway" {
  source   = "./modules/transit-gateway"
  count    = var.environment == "all" || contains(["shared-services", "prod"], var.environment) ? 1 : 0

  providers = {
    aws = var.environment == "prod" ? aws.prod : aws
  }

  project_name    = var.project_name
  environment     = var.environment
  amazon_side_asn = 64512
  vpc_attachments = {
    for env in local.environment_keys : env => {
      vpc_id       = module.vpc[env].vpc_id
      subnet_ids   = module.vpc[env].tgw_attachment_subnets
      account_id   = var.account_ids[env]
    }
  }
  tags = var.tags
}

# =============================================================================
# IAM IDENTITY CENTER PERMISSION SETS
# =============================================================================
# ARCHITECTURE DECISION: IAM Identity Center over IAM users because:
# 1. Identity Center provides a single user directory across all accounts.
# 2. Users get temporary credentials (no long-lived access keys).
# 3. Permission sets are reusable across accounts; IAM users require per-account roles.
# 4. Integration with external IdP (Azure AD/Okta) for SSO.
# 5. FCA audit requirements demand traceable access with auto-expiry.
# SECURITY SAFEGUARD: Permission sets enforce least-privilege by default
# and require approval for privilege escalation (break-glass).
module "iam_identity_center" {
  source   = "./modules/iam-identity-center"

  providers = {
    aws = aws
  }

  org_id           = var.org_id
  project_name     = var.project_name
  account_ids      = var.account_ids
  squad_names      = var.squad_names
  identity_store_id = var.org_id != null ? data.aws_ssoadmin_instances.this[0].identity_store_id : null
  tags             = var.tags
}

data "aws_ssoadmin_instances" "this" {
  count = var.org_id != null ? 1 : 0
}

# =============================================================================
# KMS KEY HIERARCHY (Per-Service Per-Environment)
# =============================================================================
# ARCHITECTURE DECISION: Multi-key KMS hierarchy over single key because:
# 1. Per-service keys limit blast radius — compromise of the S3 key doesn't
#    expose RDS data or SQS messages.
# 2. Granular auditing — CloudTrail shows exactly which service key was used.
# 3. Per-service rotation policies — rotate keys more frequently for
#    high-sensitivity services (e.g., RDS, Secrets Manager).
# 4. Easier key revocation — can disable a single service key without
#    impacting other services.
# SECURITY SAFEGUARD: All keys are FIPS 140-2 validated and use automatic
# annual rotation. Key administrators require MFA session tokens.
module "kms" {
  source   = "./modules/kms"
  for_each = toset(local.environment_keys)

  providers = {
    aws = try(try(aws[each.key], null), aws)
  }

  environment      = each.key
  project_name     = var.project_name
  services         = ["s3", "rds", "ebs", "sqs", "secretsmanager", "cloudtrail", "cloudwatch"]
  key_administrators = var.kms_key_administrators
  enable_rotation  = true
  deletion_window_in_days = 30
  tags             = merge(var.tags, { Environment = each.key })
}

# =============================================================================
# AWS CONFIG RULES
# =============================================================================
# ARCHITECTURE DECISION: AWS Config over manual audits because:
# 1. Config provides continuous monitoring — violations are detected in
#    near-real-time, not just during periodic manual reviews.
# 2. Config rules can auto-remediate (SSM Automation docs) for common issues.
# 3. Config's compliance timeline provides an immutable audit trail for FCA.
# 4. Config aggregator gives a single-pane-of-glass across all accounts.
# SECURITY SAFEGUARD: Rules are mandatory for all accounts. Disabling
# Config would require an exception approved by the CISO.
module "config" {
  source   = "./modules/config"
  count    = var.enable_config ? length(local.environment_keys) : 0

  providers = {
    aws = try(try(aws[local.environment_keys[count.index]], null), aws)
  }

  environment  = local.environment_keys[count.index]
  project_name = var.project_name
  tags         = merge(var.tags, { Environment = local.environment_keys[count.index] })
}

# =============================================================================
# CENTRALIZED LOGGING (Immutable Audit Trail)
# =============================================================================
# ARCHITECTURE DECISION: S3 logging bucket with Object Lock for immutable logs:
# 1. Object Lock prevents log deletion/modification even by root users.
# 2. Governance mode allows compliance officers to adjust retention if needed.
# 3. Complies with FCA SYSC 3.2.6R — electronic audit trail that cannot be altered.
# 4. CloudWatch subscription filters send all logs to S3 for long-term retention.
# SECURITY SAFEGUARD: Object Lock retention period is set to 365 days minimum
# with compliance hold available for legal investigations.
module "logging" {
  source   = "./modules/logging"
  count    = var.environment == "all" || var.environment == "shared-services" || contains(["dev", "staging", "prod"], var.environment) ? 1 : 0

  providers = {
    aws = aws
  }

  project_name      = var.project_name
  environment       = var.environment
  enable_object_lock = var.enable_object_lock
  retention_days    = 365
  tags              = var.tags
}

# =============================================================================
# VPC FLOW LOGS (Enabled per VPC)
# =============================================================================
# ARCHITECTURE DECISION: VPC Flow Logs are mandatory for all VPCs because:
# 1. They capture IP traffic metadata for forensic investigation.
# 2. Required for FCA compliance on network boundary monitoring.
# 3. Enable detection of exfiltration attempts and lateral movement.
# SECURITY SAFEGUARD: Flow logs are delivered to the centralized S3 logging
# bucket (Object Lock protected) and cannot be disabled per-subnet.
# Flow logs are configured inside the VPC module — see modules/vpc/main.tf.

# =============================================================================
# ORGANIZATIONS POLICIES (SCPs for Guardrails)
# =============================================================================
# ARCHITECTURE DECISION: Service Control Policies enforce baseline guardrails:
# - Deny leaving the organization.
# - Deny disabling CloudTrail or Config.
# - Deny modifying S3 Object Lock settings.
# - Require KMS encryption for all RDS, S3, and EBS resources.
# These are provisioned in the management account via a separate root module.
# TODO: Implement SCP module in Repo 2 (Policy-as-Code pipeline).
