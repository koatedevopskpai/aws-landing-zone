output "vpc_ids" {
  description = "Map of VPC IDs per environment created by the landing zone."
  value = {
    for env, account_key in var.account_ids : env => module.vpc[env].vpc_id
  }
  sensitive = false
}

output "transit_gateway_id" {
  description = "ID of the Transit Gateway in the shared-services account for cross-VPC routing."
  value       = try(module.transit_gateway[0].tgw_id, null)
}

output "kms_key_arns" {
  description = "ARNs of KMS keys created per service per environment."
  value       = module.kms[*].key_arns
}

output "config_role_arn" {
  description = "IAM role ARN used by AWS Config for recording and rule evaluation."
  value       = try(module.config[0].config_role_arn, null)
}

output "log_bucket_name" {
  description = "Name of the S3 bucket for centralized logging with Object Lock enabled."
  value       = try(module.logging[0].log_bucket_name, null)
}

output "identity_center_permission_sets" {
  description = "Map of squad permission set ARNs created in IAM Identity Center."
  value       = module.iam_identity_center.permission_set_arns
}
