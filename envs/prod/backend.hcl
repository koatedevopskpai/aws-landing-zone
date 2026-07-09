# ARCHITECTURE DECISION: Prod backend uses the same bucket with KMS encryption.
# A separate DynamoDB lock table could be used for stricter isolation.
# SECURITY SAFEGUARD: Prod state contains sensitive data (account IDs, CIDRs).
# KMS encryption ensures state is encrypted at rest.
bucket         = "secondwave-terraform-state-111111111111"
key            = "landing-zone/envs/prod/terraform.tfstate"
region         = "eu-west-2"
encrypt        = true
kms_key_id     = "alias/terraform-state-key"
dynamodb_table = "terraform-state-lock"
