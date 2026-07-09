#!/bin/bash
# =============================================================================
# BOOTSTRAP-BACKEND.SH — Create Terraform State Infrastructure
# =============================================================================
# ARCHITECTURE DECISION: This script creates the infrastructure needed for
# Terraform remote state BEFORE Terraform can manage it itself (chicken-and-egg).
# The S3 bucket and DynamoDB table must exist before terraform init can run.
#
# Chicken-and-egg explanation:
# 1. Terraform needs a remote backend to store state (S3 + DynamoDB).
# 2. But we can't use Terraform to create the backend because we need
#    somewhere to store the state for that Terraform run.
# 3. Solution: Use this shell script (or CloudFormation/CLI) once to bootstrap.
# 4. After bootstrap, ALL infrastructure (including this bucket) can be managed
#    by Terraform — import the existing resources into state.
#
# ARCHITECTURE DECISION: Using AWS CLI directly for bootstrap because:
# - It's a one-time operation per organization.
# - We don't want Terraform to have a dependency on its own backend.
# - Explicit CLI commands with error handling are easier to audit.
#
# SECURITY SAFEGUARD: State bucket has:
# - Versioning enabled (state recovery from accidental deletion)
# - Server-side encryption with KMS (state may contain secrets)
# - Public access blocked (state could leak account IDs/VPC CIDRs)
# - DynamoDB locking (prevent concurrent state modifications)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# === CONFIGURATION ===
# ARCHITECTURE DECISION: Default region is London (eu-west-2) for UK fintech.
# Change these values for your organization.
readonly STATE_BUCKET="secondwave-terraform-state-$(aws sts get-caller-identity --query Account --output text)"
readonly DYNAMODB_TABLE="terraform-state-lock"
readonly REGION="eu-west-2"
readonly KMS_ALIAS="alias/terraform-state-key"

echo "=== Bootstrap: Terraform State Backend ==="
echo "Account:  $(aws sts get-caller-identity --query Account --output text)"
echo "Region:   ${REGION}"
echo "Bucket:   ${STATE_BUCKET}"
echo "DynamoDB: ${DYNAMODB_TABLE}"
echo ""

# === Step 1: Create S3 State Bucket ===
echo ">>> Creating S3 state bucket..."
if aws s3api head-bucket --bucket "${STATE_BUCKET}" 2>/dev/null; then
  echo "Bucket ${STATE_BUCKET} already exists. Skipping."
else
  # ARCHITECTURE DECISION: us-east-1 is required for creating buckets
  # without LocationConstraint. We override to our region.
  aws s3api create-bucket \
    --bucket "${STATE_BUCKET}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"

  # SECURITY SAFEGUARD: Block all public access
  aws s3api put-public-access-block \
    --bucket "${STATE_BUCKET}" \
    --public-access-block-configuration \
      BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

  # SECURITY SAFEGUARD: Enable versioning for state recovery
  aws s3api put-bucket-versioning \
    --bucket "${STATE_BUCKET}" \
    --versioning-configuration Status=Enabled

  # SECURITY SAFEGUARD: Enable server-side encryption
  # Using AES256 for bootstrap simplicity; production should use KMS.
  aws s3api put-bucket-encryption \
    --bucket "${STATE_BUCKET}" \
    --server-side-encryption-configuration '{
      "Rules": [
        {
          "ApplyServerSideEncryptionByDefault": {
            "SSEAlgorithm": "AES256"
          }
        }
      ]
    }'

  echo "Bucket ${STATE_BUCKET} created."
fi
echo ""

# === Step 2: Create DynamoDB Lock Table ===
echo ">>> Creating DynamoDB lock table..."
if aws dynamodb describe-table --table-name "${DYNAMODB_TABLE}" 2>/dev/null; then
  echo "Table ${DYNAMODB_TABLE} already exists. Skipping."
else
  # ARCHITECTURE DECISION: Pay-per-request billing for low-traffic state locking.
  # Provisioned capacity would be wasteful since locks are acquired briefly.
  aws dynamodb create-table \
    --table-name "${DYNAMODB_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"

  echo "Table ${DYNAMODB_TABLE} created."

  # Wait for table to be active
  aws dynamodb wait table-exists --table-name "${DYNAMODB_TABLE}"
  echo "Table ${DYNAMODB_TABLE} is active."
fi
echo ""

# === Step 3: Create KMS Key for State Encryption (Optional) ===
# ARCHITECTURE DECISION: KMS key for state encryption is optional at bootstrap.
# AES256 is sufficient for initial state; upgrade to KMS after Terraform is running.
echo ">>> Checking KMS key for state encryption..."
if aws kms describe-key --key-id "${KMS_ALIAS}" 2>/dev/null; then
  echo "KMS key ${KMS_ALIAS} already exists."
  KMS_KEY_ID=$(aws kms describe-key --key-id "${KMS_ALIAS}" --query KeyMetadata.KeyId --output text)
else
  echo "KMS key ${KMS_ALIAS} not found."
  echo "Create manually after bootstrap:"
  echo "  aws kms create-key --description 'Terraform State Encryption Key'"
  echo "  aws kms create-alias --alias-name ${KMS_ALIAS} --target-key-id <key-id>"
  echo ""
  echo "For now, AES256 encryption will be used for the state bucket."
  KMS_KEY_ID=""
fi
echo ""

# === Summary ===
echo "=== Bootstrap Complete ==="
echo "Update your backend configuration in versions.tf:"
echo ""
echo "terraform {"
echo "  backend \"s3\" {"
echo "    bucket         = \"${STATE_BUCKET}\""
echo "    key            = \"landing-zone/terraform.tfstate\""
echo "    region         = \"${REGION}\""
echo "    encrypt        = true"
if [ -n "${KMS_KEY_ID}" ]; then
echo "    kms_key_id     = \"${KMS_ALIAS}\""
fi
echo "    dynamodb_table = \"${DYNAMODB_TABLE}\""
echo "  }"
echo "}"
echo ""
echo "SECURITY SAFEGUARD: Ensure the bucket policy restricts access to"
echo "authorized Terraform execution roles only. Use aws s3api put-bucket-policy."
