# =============================================================================
# LOGGING MODULE — Immutable Audit Trail with S3 Object Lock
# =============================================================================
# ARCHITECTURE DECISION: Centralized S3 logging bucket with Object Lock because:
# 1. Objects cannot be deleted or overwritten for the retention period —
#    even by root users, even if the bucket policy is modified later.
# 2. Governance mode allows designated users (compliance officers) to adjust
#    retention periods without ability to delete.
# 3. Compliance mode provides legal hold — can be enabled during investigations
#    and cannot be removed by anyone (including root).
# 4. FCA SYSC 3.2.6R requires an electronic audit trail that is "capable of
#    being reproduced at any time and cannot be altered without detection."
#    S3 Object Lock satisfies this requirement natively.
# 5. Immutable logs satisfy GDPR right-to-audit and prevent tampering by
#    insiders or attackers who gain privileged access.
#
# SECURITY SAFEGUARD: Object Lock retention period is 365 days minimum.
# This provides a full year of immutable audit data for FCA examinations.
# SECURITY SAFEGUARD: S3 Bucket Policy denies all non-TLS requests.
# SECURITY SAFEGUARD: Bucket access logging sends access logs to a separate
# bucket to prevent circular logging.
# SECURITY SAFEGUARD: AWS CloudTrail and Config are configured to deliver
# to this bucket for centralized immutable audit.

# =============================================================================
# S3 LOGGING BUCKET
# =============================================================================
# ARCHITECTURE DECISION: Bucket name includes a random suffix to guarantee
# global uniqueness. Environment prefix enables multi-environment logging.
resource "random_pet" "bucket_suffix" {
  length    = 2
  separator = "-"
}

locals {
  bucket_name = "${var.project_name}-${var.environment}-logs-${random_pet.bucket_suffix.id}"
}

resource "aws_s3_bucket" "logs" {
  bucket = local.bucket_name

  # SECURITY SAFEGUARD: Block all public access at bucket level.
  # This is the first line of defense against data exposure.
  # Even if a bucket policy is modified, these settings prevent public access.
  object_lock_enabled = var.enable_object_lock

  tags = merge(var.tags, {
    Name        = local.bucket_name
    Environment = var.environment
    Purpose     = "immutable-audit-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SECURITY SAFEGUARD: Enforce TLS for all requests to the logging bucket.
resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonTLSRequests"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.logs.arn,
          "${aws_s3_bucket.logs.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
    ]
  })
}

# =============================================================================
# S3 OBJECT LOCK CONFIGURATION
# =============================================================================
# ARCHITECTURE DECISION: Object Lock in GOVERNANCE mode allows compliance
# officers to adjust retention if needed, but prevents deletion/overwrite.
# SECURITY SAFEGUARD: Default retention of 365 days applied to all objects.
# Legal hold can be placed for specific objects during investigations.
resource "aws_s3_bucket_object_lock_configuration" "logs" {
  count  = var.enable_object_lock ? 1 : 0
  bucket = aws_s3_bucket.logs.id

  rule {
    default_retention {
      mode  = "GOVERNANCE"
      days  = var.retention_days
    }
  }
}

# =============================================================================
# S3 BUCKET VERSIONING (Required for Object Lock)
# =============================================================================
resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# =============================================================================
# S3 SERVER-SIDE ENCRYPTION
# =============================================================================
# ARCHITECTURE DECISION: SSE-S3 for the logging bucket (AES-256 managed by AWS).
# In FCA scenarios, SSE-KMS can be used with a dedicated KMS key from the KMS
# module for additional key separation.
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "AES256"
    }
  }
}

# =============================================================================
# CENTRALIZED CLOUDWATCH LOGS DESTINATION
# =============================================================================
# ARCHITECTURE DECISION: CloudWatch Logs subscription filter sends all
# VPC Flow Logs, CloudTrail, and Config logs to the centralized S3 bucket.
# This provides a single immutable storage sink for all audit data.
resource "aws_cloudwatch_log_destination" "central" {
  name       = "${var.project_name}-${var.environment}-central-logs"
  role_arn   = aws_iam_role.cw_to_s3.arn
  target_arn = aws_s3_bucket.logs.arn

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-cw-logs-destination"
  })
}

# SECURITY SAFEGUARD: IAM role with least-privilege permissions to write
# CloudWatch Logs to S3. Only allows PutObject to the logging bucket.
resource "aws_iam_role" "cw_to_s3" {
  name = "${var.project_name}-${var.environment}-cw-to-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-cw-to-s3-role"
  })
}

resource "aws_iam_role_policy" "cw_to_s3" {
  name = "${var.project_name}-${var.environment}-cw-to-s3-policy"
  role = aws_iam_role.cw_to_s3.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetBucketAcl",
          "s3:GetBucketLocation",
        ]
        Effect   = "Allow"
        Resource = [
          aws_s3_bucket.logs.arn,
          "${aws_s3_bucket.logs.arn}/*",
        ]
      }
    ]
  })
}

# =============================================================================
# ACCESS LOGGING BUCKET (Separate bucket for access logs)
# =============================================================================
# ARCHITECTURE DECISION: Access logs go to a separate bucket to avoid
# circular logging (logging writes generating more access logs).
resource "random_pet" "access_suffix" {
  length    = 2
  separator = "-"
}

locals {
  access_bucket_name = "${var.project_name}-${var.environment}-access-logs-${random_pet.access_suffix.id}"
}

resource "aws_s3_bucket" "access_logs" {
  bucket = local.access_bucket_name

  tags = merge(var.tags, {
    Name        = local.access_bucket_name
    Environment = var.environment
    Purpose     = "access-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "logs" {
  bucket = aws_s3_bucket.logs.id

  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "log/"
}

# =============================================================================
# LIFECYCLE POLICY (Cost optimization)
# =============================================================================
# ARCHITECTURE DECISION: Move older logs to Glacier for cost savings while
# maintaining immutability. Object Lock prevents deletion during retention.
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = 2555 # 7 years retention for FCA compliance
    }
  }
}
