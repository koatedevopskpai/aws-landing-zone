output "config_role_arn" {
  description = "ARN of the IAM role used by AWS Config."
  value       = aws_iam_role.config.arn
}

output "config_recorder_name" {
  description = "Name of the AWS Config recorder."
  value       = aws_config_configuration_recorder.this.name
}

output "delivery_channel_name" {
  description = "Name of the Config delivery channel."
  value       = aws_config_delivery_channel.this.name
}

output "rule_names" {
  description = "List of Config rule names created."
  value = compact([
    try(aws_config_config_rule.s3_bucket_public_read_prohibited[0].name, ""),
    try(aws_config_config_rule.encrypted_volumes[0].name, ""),
    try(aws_config_config_rule.vpc_flow_logs_enabled[0].name, ""),
    try(aws_config_config_rule.rds_encrypted[0].name, ""),
    try(aws_config_config_rule.cloudtrail_cloudwatch[0].name, ""),
    try(aws_config_config_rule.s3_ssl_requests[0].name, ""),
    try(aws_config_config_rule.iam_mfa[0].name, ""),
  ])
}
