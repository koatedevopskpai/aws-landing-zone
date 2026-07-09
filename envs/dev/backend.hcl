# ARCHITECTURE DECISION: Dev environment uses the same state bucket as other
# environments but with a separate key path. This isolates state files while
# using a single bucket for simplicity.
bucket         = "secondwave-terraform-state-111111111111"
key            = "landing-zone/envs/dev/terraform.tfstate"
region         = "eu-west-2"
encrypt        = true
kms_key_id     = "alias/terraform-state-key"
dynamodb_table = "terraform-state-lock"
