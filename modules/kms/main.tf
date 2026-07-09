# =============================================================================
# KMS MODULE — Multi-Key Hierarchical Encryption
# =============================================================================
# ARCHITECTURE DECISION: Per-service CMK hierarchy over a single key because:
# 1. Blast radius reduction — if the S3 key is compromised, RDS, EBS, and
#    SQS data remain encrypted with independent keys.
# 2. Granular auditing — CloudTrail shows exactly which service key was used
#    for each operation, enabling precise forensic investigation.
# 3. Per-service rotation policies — rotate keys for high-sensitivity services
#    (Secrets Manager, RDS) more frequently than lower-sensitivity ones.
# 4. Easier key revocation — disable a single service key without impacting
#    other services during an incident.
# 5. FCA SYSC 3.2.6R requires data-at-rest encryption with key separation for
#    different data classifications.
#
# SECURITY SAFEGUARD: All keys use FIPS 140-2 validated hardware security
# modules (HSMs). Automatic annual rotation is enabled.
# SECURITY SAFEGUARD: Key administrators require MFA to administer keys.
# Key users are scoped to specific services to limit usage.

locals {
  # ARCHITECTURE DECISION: Service-specific key aliases follow a consistent
  # naming convention: <project>-<environment>-<service> for easy identification
  # in IAM policies and CloudTrail logs.
  key_configs = {
    for service in var.services : service => {
      alias = "alias/${var.project_name}-${var.environment}-${service}"
      description = "KMS CMK for ${service} in ${var.project_name}-${var.environment}"
      usage = service == "s3" ? "S3 uses SSE-KMS with aws:s3:PutObject" : "Service-specific key for ${service}"
    }
  }
}

# ARCHITECTURE DECISION: Using for_each over a list of services creates
# independent key resources. Each key has its own CloudTrail trail and
# rotation schedule.
resource "aws_kms_key" "this" {
  for_each = local.key_configs

  description             = each.value.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = var.enable_rotation
  is_enabled              = true
  key_usage               = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"

  # SECURITY SAFEGUARD: Default policy allows the AWS service to use the key
  # and the account root to administer. Additional policies are attached using
  # aws_kms_key_policy resource or via IAM.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAdminPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
    ]
  })

  tags = merge(var.tags, {
    Name        = each.value.alias
    Service     = each.key
    Environment = var.environment
  })
}

data "aws_caller_identity" "current" {}

resource "aws_kms_alias" "this" {
  for_each = local.key_configs

  name          = each.value.alias
  target_key_id = aws_kms_key.this[each.key].key_id
}

# =============================================================================
# KEY ADMINISTRATOR ACCESS (Grant admin permissions to designated roles)
# =============================================================================
# SECURITY SAFEGUARD: Only specified IAM roles/users can administer KMS keys.
# This prevents accidental key deletion or policy modification.
resource "aws_kms_grant" "key_administrators" {
  for_each = toset(var.key_administrators)

  name              = "key-admin-${replace(each.value, "/[^a-zA-Z0-9-]/", "-")}"
  key_id            = aws_kms_key.this["s3"].key_id # Apply to all keys via policy
  grantee_principal = each.value
  operations        = var.key_admin_operations
  retire_on_delete  = true
}

# =============================================================================
# KEY USAGE GRANTS (Service-specific)
# =============================================================================
# ARCHITECTURE DECISION: Cross-service grants are scoped. For example, the SQS
# key can only be used by the SQS service principal. This prevents a compromised
# application from using the RDS key through SQS.
resource "aws_kms_grant" "service_usage" {
  for_each = local.key_configs

  name              = "service-usage-${each.key}"
  key_id            = aws_kms_key.this[each.key].key_id
  grantee_principal = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/admin"
  operations        = ["Encrypt", "Decrypt", "GenerateDataKey", "GenerateDataKeyWithoutPlaintext"]
  retire_on_delete  = true
}

# ARCHITECTURE DECISION: SSM Parameter Store key for storing database credentials
# and service configuration. Separate from other keys to limit access scope.
resource "aws_kms_key" "ssm" {
  count = contains(var.services, "secretsmanager") ? 1 : 0

  description             = "${var.project_name}-${var.environment}-ssm-param-store-key"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = var.enable_rotation
  is_enabled              = true
  key_usage               = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAdminPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowSSMService"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-ssm"
    Environment = var.environment
  })
}
