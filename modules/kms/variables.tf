variable "environment" {
  description = "Environment name (dev, staging, prod, shared-services)."
  type        = string
}

variable "project_name" {
  description = "Project name for key aliases."
  type        = string
}

variable "services" {
  description = "List of AWS services to create KMS keys for."
  type        = list(string)
  default     = ["s3", "rds", "ebs", "sqs", "secretsmanager", "cloudtrail", "cloudwatch"]
}

variable "key_administrators" {
  description = "List of IAM ARNs allowed to administer keys."
  type        = list(string)
  default     = []
  sensitive   = true
}

variable "key_admin_operations" {
  description = "List of KMS operations allowed for administrators."
  type        = list(string)
  default     = [
    "CreateKey",
    "Encrypt",
    "Decrypt",
    "GenerateDataKey",
    "DescribeKey",
    "ScheduleKeyDeletion",
    "CancelKeyDeletion",
    "PutKeyPolicy",
    "GetKeyPolicy",
    "ListKeyPolicies",
    "TagResource",
    "UntagResource",
    "EnableKeyRotation",
    "DisableKeyRotation",
  ]
}

variable "enable_rotation" {
  description = "Enable automatic annual key rotation."
  type        = bool
  default     = true
}

variable "deletion_window_in_days" {
  description = "Waiting period before KMS key deletion (7-30 days)."
  type        = number
  default     = 30
  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "Deletion window must be between 7 and 30 days."
  }
}

variable "tags" {
  description = "Common tags applied to all keys."
  type        = map(string)
  default     = {}
}
