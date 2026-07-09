# ARCHITECTURE DECISION: Minimum Terraform 1.3+ required for optional() and improved type constraints.
# ARCHITECTURE DECISION: AWS provider >= 5.0 for native Terraform AWS provider support for IAM Identity Center, Organizations, and Transit Gateway.
# ARCHITECTURE DECISION: Random provider for generating unique suffixes (e.g., bucket names) without collision.
# SECURITY SAFEGUARD: Pinning provider versions prevents unexpected upgrades that could break compliance controls or introduce breaking changes.
terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0, < 6.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0, < 4.0.0"
    }
  }

  # ARCHITECTURE DECISION: S3 backend with DynamoDB locking for state safety.
  # SECURITY SAFEGUARD: State bucket must have versioning, encryption, and public access blocked.
  # This block is COMMENTED to demonstrate the pattern; uncomment after bootstrap (see scripts/bootstrap-backend.sh).
  # backend "s3" {
  #   bucket         = "secondwave-terraform-state-123456789012"
  #   key            = "landing-zone/terraform.tfstate"
  #   region         = "eu-west-2"
  #   encrypt        = true
  #   kms_key_id     = "alias/terraform-state-key"
  #   dynamodb_table = "terraform-state-lock"
  # }
}
