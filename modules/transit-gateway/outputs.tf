output "tgw_id" {
  description = "ID of the Transit Gateway."
  value       = aws_ec2_transit_gateway.this.id
}

output "tgw_arn" {
  description = "ARN of the Transit Gateway."
  value       = aws_ec2_transit_gateway.this.arn
}

output "trusted_route_table_id" {
  description = "ID of the trusted (prod + shared-services) route table."
  value       = aws_ec2_transit_gateway_route_table.trusted.id
}

output "non_production_route_table_id" {
  description = "ID of the non-production route table."
  value       = aws_ec2_transit_gateway_route_table.non_production.id
}

output "attachment_ids" {
  description = "Map of environment to TGW attachment ID."
  value       = { for k, v in aws_ec2_transit_gateway_vpc_attachment.this : k => v.id }
}
