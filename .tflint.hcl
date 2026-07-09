# =============================================================================
# TFLINT CONFIGURATION — AWS-Specific Linting
# =============================================================================
# ARCHITECTURE DECISION: TFLint enforces AWS best practices that cannot
# be expressed in Terraform's type system.
# SECURITY SAFEGUARD: Rules detect common security misconfigurations
# before they reach production.

config {
  module = true
  force  = false
}

plugin "aws" {
  enabled = true
  version = "0.27.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# SECURITY SAFEGUARD: Warn about default security group rules (allow all).
rule "aws_security_group_rule" {
  enabled = true
}

# SECURITY SAFEGUARD: Require S3 bucket public access block.
rule "aws_s3_bucket_public_access_block" {
  enabled = true
}

# SECURITY SAFEGUARD: Require S3 bucket logging.
rule "aws_s3_bucket_logging" {
  enabled = true
}

# SECURITY SAFEGUARD: Require S3 bucket versioning.
rule "aws_s3_bucket_versioning" {
  enabled = true
}

# SECURITY SAFEGUARD: Require S3 bucket encryption.
rule "aws_s3_bucket_encryption" {
  enabled = true
}

# SECURITY SAFEGUARD: Warn about public-facing resources.
rule "aws_db_instance_default_parameter_group" {
  enabled = true
}

# SECURITY SAFEGUARD: Ensure CloudTrail is enabled.
rule "aws_cloudtrail_bucket_logging" {
  enabled = true
}

# ARCHITECTURE DECISION: Enforce tagging conventions.
rule "aws_resource_missing_tags" {
  enabled = true
  tags = ["Project", "Environment", "ManagedBy", "Name"]
}

# ARCHITECTURE DECISION: Validate instance types and sizes.
rule "aws_instance_invalid_type" {
  enabled = true
}

# ARCHITECTURE DECISION: Validate EBS volume types.
rule "aws_ebs_volume_invalid_type" {
  enabled = true
}
