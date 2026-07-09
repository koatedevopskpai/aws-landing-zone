variable "project_name" {
  description = "Project name for bucket naming."
  type        = string
}

variable "environment" {
  description = "Environment name (shared-services, dev, staging, prod)."
  type        = string
}

variable "enable_object_lock" {
  description = "Enable S3 Object Lock for immutable log storage."
  type        = bool
  default     = true
}

variable "retention_days" {
  description = "Default Object Lock retention period in days."
  type        = number
  default     = 365
  validation {
    condition     = var.retention_days >= 90 && var.retention_days <= 3650
    error_message = "Retention days must be between 90 and 3650."
  }
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
