# Staging environment — production-like validation
environment = "staging"

account_ids = {
  shared-services = "111111111111"
  dev             = "222222222222"
  staging         = "333333333333"
  prod            = "444444444444"
}

org_id = "o-abc123def"

environments = {
  staging = {
    region           = "eu-west-2"
    dr_region        = null
    enable_natgw     = true
    enable_vpn       = false
    enable_flow_logs = true
  }
}

enable_config     = true
enable_object_lock = true

# SECURITY SAFEGUARD: Staging encryption should mirror prod for realistic testing.
kms_key_administrators = [
  "arn:aws:iam::111111111111:role/TerraformExecutionRole",
]
