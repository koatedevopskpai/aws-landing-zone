variable "org_id" {
  description = "AWS Organizations ID."
  type        = string
  default     = null
}

variable "project_name" {
  description = "Project name for permission set naming."
  type        = string
}

variable "account_ids" {
  description = "Map of environment names to AWS account IDs."
  type        = map(string)
  sensitive   = true
}

variable "squad_names" {
  description = "List of squad names for permission set creation."
  type        = list(string)
}

variable "identity_store_id" {
  description = "Identity Store ID for IAM Identity Center."
  type        = string
  default     = null
}

variable "tags" {
  description = "Common tags applied to permission sets."
  type        = map(string)
  default     = {}
}
