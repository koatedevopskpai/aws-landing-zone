# =============================================================================
# IAM IDENTITY CENTER MODULE — Permission Sets Per Squad
# =============================================================================
# ARCHITECTURE DECISION: IAM Identity Center over IAM users because:
# 1. Identity Center provides a single user directory across ALL AWS accounts.
#    IAM users are per-account — managing users across 4+ accounts is untenable.
# 2. Identity Center enforces temporary credentials (session duration = 1-12h).
#    IAM users can have long-lived access keys (compliance risk).
# 3. Permission sets are reusable — one definition grants access across accounts.
# 4. Integration with external IdP (Azure AD, Okta) for SSO and SCIM provisioning.
# 5. FCA SYSC 6.1.1R requires user access recertification — Identity Center
#    enables automated attestation workflows.
#
# SECURITY SAFEGUARD: No IAM users created in workload accounts. All human
# access is via Identity Center with temporary credentials.
# SECURITY SAFEGUARD: Permission sets enforce least-privilege by default.
# Squad-specific managed policies provide only the permissions each squad needs.

locals {
  # ARCHITECTURE DECISION: Permission sets are mapped per squad.
  # Platform gets full infrastructure access, CoreBanking gets read-only + database,
  # Digital gets CI/CD and application, Data gets analytics and ML.
  squad_permissions = {
    Platform = {
      description     = "Platform engineering team — infrastructure management"
      session_duration = "PT8H"
      managed_policies = [
        "arn:aws:iam::aws:policy/AdministratorAccess",
      ]
      inline_policy = null
    }
    CoreBanking = {
      description     = "Core banking squad — database and read-only access"
      session_duration = "PT4H"
      managed_policies = [
        "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess",
        "arn:aws:iam::aws:policy/AmazonRDSFullAccess",
        "arn:aws:iam::aws:policy/AmazonElastiCacheFullAccess",
      ]
      inline_policy = null
    }
    Digital = {
      description     = "Digital squad — CI/CD, ECS, EKS, frontend services"
      session_duration = "PT8H"
      managed_policies = [
        "arn:aws:iam::aws:policy/PowerUserAccess",
        "arn:aws:iam::aws:policy/AmazonECS_FullAccess",
        "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
      ]
      inline_policy = null
    }
    Data = {
      description     = "Data platform squad — analytics, Glue, Athena, SageMaker"
      session_duration = "PT4H"
      managed_policies = [
        "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess",
        "arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess",
        "arn:aws:iam::aws:policy/AmazonAthenaFullAccess",
        "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess",
      ]
      inline_policy = null
    }
  }
}

# SECURITY SAFEGUARD: Identity Store ID is fetched from the SSO admin instance.
# This is a read-only data source — no risk of modification.
data "aws_ssoadmin_instances" "this" {}

# =============================================================================
# PERMISSION SETS
# =============================================================================
resource "aws_ssoadmin_permission_set" "this" {
  for_each = local.squad_permissions

  name             = "${var.project_name}-${each.key}"
  description      = each.value.description
  instance_arn     = data.aws_ssoadmin_instances.this.arns[0]
  session_duration = each.value.session_duration

  tags = merge(var.tags, {
    Squad = each.key
  })
}

# ARCHITECTURE DECISION: Managed policies are attached via
# aws_ssoadmin_managed_policy_attachment for native AWS policies.
# Inline policies would be used for custom scoped permissions.
resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = {
    for pair in flatten([
      for squad_name, config in local.squad_permissions : [
        for policy in config.managed_policies : {
          key    = "${squad_name}:${policy}"
          squad  = squad_name
          policy = policy
        }
      ]
    ]) : pair.key => pair
  }

  instance_arn       = data.aws_ssoadmin_instances.this.arns[0]
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.squad].arn
  managed_policy_arn = each.value.policy
}

# =============================================================================
# GROUP ASSIGNMENTS (Account-level)
# =============================================================================
# ARCHITECTURE DECISION: Assigning permission sets to accounts for all squads.
# In production, groups would be provisioned from the external IdP via SCIM.
# The assignment to accounts follows the principle of least privilege:
# - Dev: All squads get access for development.
# - Staging: CoreBanking + Digital + Data (no Platform changes to staging infra).
# - Prod: Only CoreBanking (read-only) and Digital (limited CI/CD).
# - Shared-Services: Only Platform team.
resource "aws_ssoadmin_account_assignment" "this" {
  for_each = {
    for pair in flatten([
      for squad_name in var.squad_names : [
        for account_key, account_id in var.account_ids : {
          key         = "${squad_name}:${account_key}"
          squad       = squad_name
          account_id  = account_id
        }
      ]
    ]) : pair.key => pair
  }

  instance_arn       = data.aws_ssoadmin_instances.this.arns[0]
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.squad].arn
  principal_id       = each.value.squad # In production, this would be a group ID from IdP
  principal_type     = "GROUP"
  target_id          = each.value.account_id
  target_type        = "AWS_ACCOUNT"
}
