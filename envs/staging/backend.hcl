# ARCHITECTURE DECISION: Staging uses the same state bucket. Separate key path
# ensures state isolation. DynamoDB locking prevents concurrent modifications.
bucket         = "secondwave-terraform-state-111111111111"
key            = "landing-zone/envs/staging/terraform.tfstate"
region         = "eu-west-2"
encrypt        = true
kms_key_id     = "alias/terraform-state-key"
dynamodb_table = "terraform-state-lock"
