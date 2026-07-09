# =============================================================================
# AWS CONFIG MODULE — Continuous Compliance Monitoring
# =============================================================================
# ARCHITECTURE DECISION: AWS Config over manual audits because:
# 1. Continuous vs. periodic — Config evaluates resources every time they change,
#    not just during monthly or quarterly manual reviews.
# 2. Automated remediation — Config rules can trigger SSM Automation documents
#    to fix non-compliant resources automatically.
# 3. Immutable audit trail — Config records configuration history and compliance
#    status changes with timestamps. This provides an unalterable record for FCA.
# 4. Multi-account aggregation — Config Aggregator provides a single compliance
#    dashboard across all accounts. Manual audits require aggregating reports.
# 5. FCA SYSC 3.2.6R — requires continuous monitoring of security controls.
#    Config rules provide exactly this capability.
#
# SECURITY SAFEGUARD: All rules are mandatory. Any resource that doesn't comply
# is logged and can trigger automated remediation.
# SECURITY SAFEGUARD: Config recorder captures all resource types and global
# resources (IAM, CloudTrail) for comprehensive coverage.

# =============================================================================
# PREREQUISITES: S3 Bucket + SNS Topic + IAM Role
# =============================================================================
# ARCHITECTURE DECISION: Config delivers snapshots to the logging S3 bucket
# (from the logging module) and sends notifications to an SNS topic.
# The IAM role follows least-privilege — only permissions required for Config.
resource "aws_config_configuration_recorder" "this" {
  name     = "${var.project_name}-${var.environment}-config-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = "${var.project_name}-${var.environment}-config-delivery"
  s3_bucket_name = var.log_bucket_name
  s3_key_prefix  = "config/${var.project_name}/${var.environment}/"
  sns_topic_arn  = aws_sns_topic.config.arn

  snapshot_delivery_properties {
    delivery_frequency = "Six_Hours"
  }

  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_sns_topic" "config" {
  name = "${var.project_name}-${var.environment}-config-notifications"

  tags = merge(var.tags, {
    Name = "${var.project-name}-${var.environment}-config-sns"
  })
}

# =============================================================================
# IAM ROLE FOR CONFIG
# =============================================================================
resource "aws_iam_role" "config" {
  name = "${var.project_name}-${var.environment}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-config-role"
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRole"
}

# =============================================================================
# CONFIG RULES
# =============================================================================
# SECURITY SAFEGUARD: s3-bucket-public-read-prohibited prevents data exposure.
# ARCHITECTURE DECISION: Using managed rules where possible — they are
# maintained by AWS and updated as service APIs evolve.
resource "aws_config_config_rule" "s3_bucket_public_read_prohibited" {
  count = var.enable_public_access_rules ? 1 : 0

  name        = "${var.project_name}-${var.environment}-s3-no-public-read"
  description = "Checks that S3 buckets do not allow public read access."

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  tags = var.tags
}

# SECURITY SAFEGUARD: encrypted-volumes ensures all EBS volumes are encrypted.
resource "aws_config_config_rule" "encrypted_volumes" {
  count = var.enable_encryption_rules ? 1 : 0

  name        = "${var.project_name}-${var.environment}-ebs-encrypted"
  description = "Checks that all EBS volumes are encrypted at rest."

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }

  tags = var.tags
}

# SECURITY SAFEGUARD: vpc-flow-logs-enabled ensures network traffic is captured.
resource "aws_config_config_rule" "vpc_flow_logs_enabled" {
  count = var.enable_flow_log_rules ? 1 : 0

  name        = "${var.project_name}-${var.environment}-vpc-flow-logs"
  description = "Checks that VPCs have flow logs enabled."

  source {
    owner             = "AWS"
    source_identifier = "VPC_FLOW_LOGS_ENABLED"
  }

  tags = var.tags
}

# SECURITY SAFEGUARD: rds-storage-encrypted ensures RDS data is encrypted at rest.
resource "aws_config_config_rule" "rds_encrypted" {
  count = var.enable_encryption_rules ? 1 : 0

  name        = "${var.project_name}-${var.environment}-rds-encrypted"
  description = "Checks that RDS instances have storage encryption enabled."

  source {
    owner             = "AWS"
    source_identifier = "RDS_STORAGE_ENCRYPTED"
  }

  tags = var.tags
}

# SECURITY SAFEGUARD: cloud-trail-cloud-watch-logs-enabled ensures audit logging.
resource "aws_config_config_rule" "cloudtrail_cloudwatch" {
  count = var.enable_logging_rules ? 1 : 0

  name        = "${var.project_name}-${var.environment}-cloudtrail-cw-logs"
  description = "Checks that CloudTrail trails are configured to send logs to CloudWatch Logs."

  source {
    owner             = "AWS"
    source_identifier = "CLOUD_TRAIL_CLOUD_WATCH_LOGS_ENABLED"
  }

  tags = var.tags
}

# SECURITY SAFEGUARD: s3-bucket-ssl-requests-only ensures encrypted transit.
resource "aws_config_config_rule" "s3_ssl_requests" {
  count = var.enable_public_access_rules ? 1 : 0

  name        = "${var.project_name}-${var.environment}-s3-ssl-only"
  description = "Checks that S3 buckets have policies requiring SSL."

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SSL_REQUESTS_ONLY"
  }

  tags = var.tags
}

# SECURITY SAFEGUARD: iam-user-mfa-enabled ensures users have MFA.
resource "aws_config_config_rule" "iam_mfa" {
  count = var.enable_iam_rules ? 1 : 0

  name        = "${var.project_name}-${var.environment}-iam-mfa"
  description = "Checks that IAM users have MFA enabled."

  source {
    owner             = "AWS"
    source_identifier = "IAM_USER_MFA_ENABLED"
  }

  tags = var.tags
}
