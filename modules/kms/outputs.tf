output "key_arns" {
  description = "Map of service names to KMS key ARNs."
  value       = { for k, v in aws_kms_key.this : k => v.arn }
}

output "key_ids" {
  description = "Map of service names to KMS key IDs."
  value       = { for k, v in aws_kms_key.this : k => v.key_id }
}

output "key_aliases" {
  description = "Map of service names to KMS key aliases."
  value       = { for k, v in aws_kms_alias.this : k => v.arn }
}

output "ssm_kms_key_arn" {
  description = "ARN of the SSM Parameter Store KMS key."
  value       = try(aws_kms_key.ssm[0].arn, null)
}
