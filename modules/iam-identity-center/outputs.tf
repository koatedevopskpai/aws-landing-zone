output "permission_set_arns" {
  description = "Map of squad names to permission set ARNs."
  value       = { for k, v in aws_ssoadmin_permission_set.this : k => v.arn }
}

output "instance_arn" {
  description = "ARN of the SSO admin instance."
  value       = data.aws_ssoadmin_instances.this.arns[0]
}

output "identity_store_id" {
  description = "Identity Store ID for user/group management."
  value       = data.aws_ssoadmin_instances.this.identity_store_ids[0]
}
