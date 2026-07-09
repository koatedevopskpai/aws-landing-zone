output "log_bucket_name" {
  description = "Name of the S3 bucket for centralized immutable logs."
  value       = aws_s3_bucket.logs.bucket
}

output "log_bucket_arn" {
  description = "ARN of the S3 logging bucket."
  value       = aws_s3_bucket.logs.arn
}

output "access_log_bucket_name" {
  description = "Name of the S3 access logs bucket."
  value       = aws_s3_bucket.access_logs.bucket
}

output "cloudwatch_log_destination_arn" {
  description = "ARN of the CloudWatch Logs destination."
  value       = aws_cloudwatch_log_destination.central.arn
}

output "cw_to_s3_role_arn" {
  description = "ARN of the IAM role for CloudWatch to S3 export."
  value       = aws_iam_role.cw_to_s3.arn
}
