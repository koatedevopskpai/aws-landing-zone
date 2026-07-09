# ADR-003: S3 Object Lock for Immutable Audit Trail

## Status

Accepted (2026-07-02)

## Context

SecondWave is FCA-regulated (Financial Conduct Authority). FCA rules require:

- **SYSC 3.2.6R:** "A firm must arrange for orderly records to be kept of its
  business and internal organisation, including all services and transactions
  undertaken by it."
- **SYSC 6.1.1R:** "A firm must establish, implement and maintain adequate
  policies and procedures to detect any risk of failure by the firm to comply
  with its obligations."

In practice, this means:
1. Logs must be immutable — cannot be deleted or modified.
2. Logs must be reproducible at any time during retention period.
3. Audit trail must cover security events, access, and configuration changes.
4. Retention period: 5+ years for FCA, 7+ years for HMRC (tax).

## Decision

We will use **S3 Object Lock in GOVERNANCE mode** with a default retention of
365 days, transitioning to Glacier for extended retention.

## Rationale

| Requirement | S3 Object Lock | Alternative (Bucket policies) |
|-------------|---------------|------------------------------|
| **Immutability** | Prevents deletion/overwrite even by root | Policy can be modified or deleted |
| **Retention enforcement** | Governance/Compliance modes + Legal Hold | Trusts principal with s3:PutObject |
| **FCA SYSC 3.2.6R** | Full compliance | Insufficient — mutable by design |
| **Forensic hold** | Legal Hold — cannot be removed by anyone | No equivalent |
| **Lifecycle integration** | Native with S3 Lifecycle policies | Manual or Lambda-based |

**Critical decider: Compliance with FCA immutability requirements.**
S3 Object Lock is the only AWS-native mechanism that guarantees objects
cannot be modified or deleted for a specified period. Bucket policies and
IAM permissions can be changed by a privileged user.

**Why not Glacier Vault Lock?**
- Glacier Vault Lock is more restrictive (can't be removed at all).
- We need GOVERNANCE mode to allow compliance officers to adjust retention
  during investigations (but not delete).
- S3 Object Lock works with Standard, IA, and Glacier tiers, enabling
  lifecycle transitions to lower cost storage while maintaining lock.

## Consequences

**Positive:**
- Full FCA compliance for audit trail immutability
- Legal Hold for forensic investigations
- Automated lifecycle management to Glacier for cost optimization
- Centralized audit sink for CloudTrail, Config, VPC Flow Logs

**Negative:**
- Additional cost for S3 storage + Object Lock (no extra fee, but retention
  prevents deletion of old data)
- Cannot delete logs even if storage cost is high (must wait for retention expiry)
- Bucket must be created with Object Lock enabled — can't be added later
- Versioning must be enabled (additional storage cost for versions)
