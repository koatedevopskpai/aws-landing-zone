variable "environment" {
  description = "Environment name (dev, staging, prod, shared-services)."
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming."
  type        = string
}

variable "log_bucket_name" {
  description = "S3 bucket name for Config snapshot delivery."
  type        = string
  default     = null
}

variable "enable_public_access_rules" {
  description = "Enable S3 public access prohibition rules."
  type        = bool
  default     = true
}

variable "enable_encryption_rules" {
  description = "Enable encryption-at-rest rules."
  type        = bool
  default     = true
}

variable "enable_flow_log_rules" {
  description = "Enable VPC flow log rules."
  type        = bool
  default     = true
}

variable "enable_logging_rules" {
  description = "Enable logging and monitoring rules."
  type        = bool
  default     = true
}

variable "enable_iam_rules" {
  description = "Enable IAM security rules."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
