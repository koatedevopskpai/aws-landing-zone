# Dev environment — lightweight, no NAT, minimal cost
environment = "dev"

account_ids = {
  shared-services = "111111111111"
  dev             = "222222222222"
  staging         = "333333333333"
  prod            = "444444444444"
}

org_id = "o-abc123def"

environments = {
  dev = {
    region           = "eu-west-2"
    dr_region        = null
    enable_natgw     = false
    enable_vpn       = false
    enable_flow_logs = true
  }
}

enable_config     = true
enable_object_lock = true
