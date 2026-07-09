# S3 Cross-Region Restore Runbook

## Objective

Restore S3 data from primary region (eu-west-2) to DR region (eu-west-1)
within RTO of 4 hours and RPO of 1 hour.

## Prerequisites

- AWS CLI configured with appropriate role (cross-account, if needed)
- S3 Batch Replication configured (see observability/dashboard.json for monitoring)
- KMS keys present in DR region for re-encryption

## RTO/RPO Guarantees

| Metric | Target | Method |
|--------|--------|--------|
| RTO | 4 hours | Pre-provisioned DR infrastructure |
| RPO | 1 hour | S3 Replication Time Control (RTC) |

## Step 1: Assess the Situation

```bash
# Check replication status
aws s3api get-bucket-replication --bucket secondwave-prod-logs-*

# Check last replicated object timestamp
aws s3api list-objects-v2 \
  --bucket secondwave-prod-logs-* \
  --region eu-west-1 \
  --max-items 1 \
  --query "Contents[0].LastModified"
```

## Step 2: Verify DR Bucket Exists

# ARCHITECTURE DECISION: DR bucket is created by Terraform in the DR region.
# If not, follow bootstrap procedure (see scripts/bootstrap-backend.sh).

```bash
aws s3api head-bucket --bucket secondwave-prod-logs-dr --region eu-west-1
```

## Step 3: Initiate Cross-Region Copy

# ARCHITECTURE DECISION: Use S3 Batch Operations for large-scale restores.
# For individual object restores, use aws s3 cp with --storage-class.

```bash
# For last 1 hour of data (RPO = 1h)
aws s3 cp s3://secondwave-prod-logs-<suffix>/ \
  s3://secondwave-prod-logs-dr/ \
  --recursive \
  --region eu-west-1 \
  --source-region eu-west-2 \
  --storage-class STANDARD
```

## Step 4: Verify Data Integrity

# ARCHITECTURE DECISION: ETag comparison verifies object integrity.
# KMS re-encryption happens automatically if key alias exists in DR region.

```bash
# Compare object counts
aws s3api list-objects-v2 --bucket secondwave-prod-logs-<suffix> --query "KeyCount"
aws s3api list-objects-v2 --bucket secondwave-prod-logs-dr --query "KeyCount"

# Spot-check specific objects
aws s3api head-object --bucket secondwave-prod-logs-<suffix> --key <object-key>
aws s3api head-object --bucket secondwave-prod-logs-dr --key <object-key>
```

## Step 5: Failover Services to DR

# Point CloudTrail, Config, and VPC Flow Logs to DR bucket.
# This requires Terraform apply in DR region with failover variables.

```bash
terraform apply -var-file="envs/prod/terraform.tfvars" \
  -var="region=eu-west-1" \
  -var="environments.prod.region=eu-west-1"
```

## Recovery Verification

- [ ] Data integrity check (ETag comparison, random sample of 100 objects)
- [ ] KMS key availability in DR region
- [ ] CloudTrail delivery to DR bucket
- [ ] Config delivery to DR bucket
- [ ] VPC Flow Logs delivery to DR bucket
- [ ] Object Lock retention applied in DR bucket
