# ARCHITECTURE DECISION: All variables have explicit types and descriptions to enforce IaC best practices and self-documenting code.
# SECURITY SAFEGUARD: Sensitive variables (e.g., account IDs) use the sensitive flag to prevent exposure in logs and outputs.

variable "org_id" {
  description = "AWS Organizations ID (e.g., o-abc123def). Used for organization-level policies and IAM Identity Center."
  type        = string
  sensitive   = false
}

variable "account_ids" {
  description = "Map of environment names to AWS account IDs. Keys: shared-services, dev, staging, prod."
  type        = map(string)
  sensitive   = true
  validation {
    condition     = alltrue([for k in keys(var.account_ids) : contains(["shared-services", "dev", "staging", "prod"], k)])
    error_message = "Account keys must be one of: shared-services, dev, staging, prod."
  }
}

variable "environments" {
  description = "Map of environment configurations including deployment regions and feature flags."
  type = map(object({
    region          = string
    dr_region       = optional(string)
    enable_natgw    = bool
    enable_vpn      = bool
    enable_flow_logs = bool
    instance_tenancy = optional(string, "default")
  }))
  default = {
    dev = {
      region           = "eu-west-2"
      dr_region        = null
      enable_natgw     = false
      enable_vpn       = false
      enable_flow_logs = true
    }
    staging = {
      region           = "eu-west-2"
      dr_region        = null
      enable_natgw     = true
      enable_vpn       = false
      enable_flow_logs = true
    }
    prod = {
      region           = "eu-west-2"
      dr_region        = "eu-west-1"
      enable_natgw     = true
      enable_vpn       = true
      enable_flow_logs = true
    }
  }
}

variable "vpc_cidrs" {
  description = "CIDR blocks per environment per account. Nested map: account_key => cidr_block."
  type = map(string)
  default = {
    shared-services = "10.0.0.0/16"
    dev             = "10.1.0.0/16"
    staging         = "10.2.0.0/16"
    prod            = "10.3.0.0/16"
  }
}

variable "region" {
  description = "Primary AWS region for deployment."
  type        = string
  default     = "eu-west-2"
}

variable "squad_names" {
  description = "List of squad names within the organisation. Each squad gets an IAM Identity Center permission set."
  type        = list(string)
  default     = ["Platform", "CoreBanking", "Digital", "Data"]
}

variable "environment" {
  description = "Deployment environment: dev, staging, or prod. Controls which resources are created and their configurations."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "secondwave"
}

variable "tags" {
  description = "Common tags applied to all resources. Must include at minimum: Environment, Project, Owner, ManagedBy."
  type        = map(string)
  default = {
    Project     = "secondwave"
    Owner       = "platform-team"
    ManagedBy   = "terraform"
  }
}

variable "kms_key_administrators" {
  description = "ARNs of IAM users/roles allowed to administer KMS keys."
  type        = list(string)
  sensitive   = true
  default     = []
}

variable "enable_config" {
  description = "Flag to enable AWS Config rules in the account."
  type        = bool
  default     = true
}

variable "enable_object_lock" {
  description = "Flag to enable S3 Object Lock on logging bucket."
  type        = bool
  default     = true
}
