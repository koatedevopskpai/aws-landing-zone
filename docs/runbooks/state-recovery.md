# Terraform State Recovery Runbook

## Objective

Recover Terraform state from accidental deletion, corruption, or lock contention.

## Prerequisites

- AWS CLI with permissions to access S3 and DynamoDB
- Backup of Terraform state (automated via S3 versioning)
- Last known good state file version

## Recovery Scenarios

### Scenario 1: State File Deleted

# ARCHITECTURE DECISION: S3 versioning is enabled on the state bucket.
# This allows recovery of previous state versions without backup restoration.

#### Step 1: Identify Deleted State

```bash
# Check if state file exists
aws s3api head-object \
  --bucket secondwave-terraform-state-111111111111 \
  --key landing-zone/terraform.tfstate

# List versions (including delete markers)
aws s3api list-object-versions \
  --bucket secondwave-terraform-state-111111111111 \
  --prefix landing-zone/terraform.tfstate
```

#### Step 2: Restore Previous Version

```bash
# Get the last good version ID
aws s3api list-object-versions \
  --bucket secondwave-terraform-state-111111111111 \
  --prefix landing-zone/terraform.tfstate \
  --query "Versions[?IsLatest==\`false\`].VersionId" \
  --output text

# Copy that version back as current
aws s3api copy-object \
  --bucket secondwave-terraform-state-111111111111 \
  --key landing-zone/terraform.tfstate \
  --copy-source secondwave-terraform-state-111111111111/landing-zone/terraform.tfstate?versionId=<VersionId>

# Remove the delete marker
aws s3api delete-object \
  --bucket secondwave-terraform-state-111111111111 \
  --key landing-zone/terraform.tfstate
```

#### Step 3: Verify State

```bash
terraform state list
```

### Scenario 2: State Lock Contention

#### Step 1: Check Lock Status

```bash
# Check DynamoDB lock table
aws dynamodb get-item \
  --table-name terraform-state-lock \
  --key '{"LockID": {"S": "secondwave-terraform-state-111111111111/landing-zone/terraform.tfstate-md5"}}'
```

#### Step 2: Force Unlock (if safe)

```bash
# Only force-unlock if you're certain no Terraform process is running.
# ARCHITECTURE DECISION: The lock ID is the same as the Terraform workspace.
# Use terraform force-unlock with the lock ID from the DynamoDB item.
terraform force-unlock <LOCK_ID>
```

### Scenario 3: State Corruption

#### Step 1: Restore from Backup

```bash
# List versions to find pre-corruption state
aws s3api list-object-versions \
  --bucket secondwave-terraform-state-111111111111 \
  --prefix landing-zone/terraform.tfstate

# Download and inspect the version before corruption
aws s3api get-object \
  --bucket secondwave-terraform-state-111111111111 \
  --key landing-zone/terraform.tfstate \
  --version-id <PreCorruptionVersionId> \
  recovered-state.tfstate

# Review for correctness
terraform show recovered-state.tfstate
```

#### Step 2: Push Recovered State

```bash
aws s3api put-object \
  --bucket secondwave-terraform-state-111111111111 \
  --key landing-zone/terraform.tfstate \
  --body recovered-state.tfstate
```

## Prevention

# SECURITY SAFEGUARD: S3 Versioning prevents permanent state loss.
# SECURITY SAFEGUARD: DynamoDB locking prevents concurrent writes.
# SECURITY SAFEGUARD: KMS encryption protects state data at rest.

- Enable S3 Versioning on state bucket (already configured)
  - See scripts/bootstrap-backend.sh
- Use DynamoDB locking (already configured)
  - See versions.tf backend configuration
- Enable S3 Access Logging for state bucket (monitor access patterns)
- Use Terraform Cloud or Terraform Enterprise for enhanced state management
