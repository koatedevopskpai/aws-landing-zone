variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod, shared-services)."
  type        = string
}

variable "project_name" {
  description = "Project name prefix for resource naming."
  type        = string
  default     = "secondwave"
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "enable_natgw" {
  description = "Enable NAT Gateway for private subnet outbound access."
  type        = bool
  default     = true
}

variable "enable_natgw_subnet_count" {
  description = "Number of NAT Gateways to provision (max 3 for multi-AZ)."
  type        = number
  default     = 3
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs (mandatory for compliance)."
  type        = bool
  default     = true
}

variable "enable_vpn" {
  description = "Enable VPN gateway attachment for the VPC."
  type        = bool
  default     = false
}

variable "instance_tenancy" {
  description = "Instance tenancy for the VPC (default or dedicated)."
  type        = string
  default     = "default"
}

variable "kms_key_arn" {
  description = "ARN of KMS key for CloudWatch Log Groups encryption."
  type        = string
  default     = null
}
