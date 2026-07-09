output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = aws_subnet.private[*].id
}

output "isolated_subnet_ids" {
  description = "IDs of the isolated (database) subnets."
  value       = aws_subnet.isolated[*].id
}

output "tgw_attachment_subnets" {
  description = "Subnet IDs for Transit Gateway attachment (public subnets)."
  value       = local.tgw_attachment_subnets
}

output "flow_log_group_name" {
  description = "CloudWatch Log Group name for VPC Flow Logs."
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].name : null
}

output "nat_gateway_ids" {
  description = "IDs of NAT Gateways (if enabled)."
  value       = var.enable_natgw ? aws_nat_gateway.this[*].id : []
}
