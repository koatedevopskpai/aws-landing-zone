# Production environment — full HA with multi-region DR
environment = "prod"

account_ids = {
  shared-services = "111111111111"
  dev             = "222222222222"
  staging         = "333333333333"
  prod            = "444444444444"
}

org_id = "o-abc123def"

environments = {
  prod = {
    region           = "eu-west-2"
    dr_region        = "eu-west-1"
    enable_natgw     = true
    enable_vpn       = true
    enable_flow_logs = true
  }
}

# ARCHITECTURE DECISION: Prod uses a different set of VPC CIDRs for DR.
vpc_cidrs = {
  shared-services = "10.0.0.0/16"
  dev             = "10.1.0.0/16"
  staging         = "10.2.0.0/16"
  prod            = "10.3.0.0/16"
}

enable_config     = true
enable_object_lock = true

# SECURITY SAFEGUARD: KMS key administrators limited to least-privilege roles.
# Requires MFA session token for key deletion operations.
kms_key_administrators = [
  "arn:aws:iam::111111111111:role/TerraformExecutionRole",
]

# SECURITY SAFEGUARD: Prod tags include compliance and criticality markers.
tags = {
  Project     = "secondwave"
  Owner       = "platform-team"
  ManagedBy   = "terraform"
  Environment = "prod"
  Compliance  = "fca-regulated"
  Criticality = "high"
}
