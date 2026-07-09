variable "project_name" {
  description = "Project name for resource naming."
  type        = string
}

variable "environment" {
  description = "Environment name (shared-services or mgmt for TGW)."
  type        = string
}

variable "amazon_side_asn" {
  description = "Private ASN for the Transit Gateway (default: 64512)."
  type        = number
  default     = 64512
}

variable "vpc_attachments" {
  description = "Map of VPC attachments. Key = environment name, value = { vpc_id, subnet_ids, account_id }."
  type = map(object({
    vpc_id     = string
    subnet_ids = list(string)
    account_id = string
  }))
  default = {}
}

variable "vpc_cidrs" {
  description = "Map of environment to VPC CIDR (for blackhole routes)."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
