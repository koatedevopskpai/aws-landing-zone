# ADR-002: Karpenter over Cluster Autoscaler for EKS Node Management

## Status

Proposed (will be elaborated in Repository 2: EKS Platform)

## Context

SecondWave will run containerized workloads on Amazon EKS. The four squads
(Platform, CoreBanking, Digital, Data) will deploy microservices with varying
resource requirements. The platform needs an automated node provisioning solution.

## Decision (Preview)

We will use **Karpenter** as the node provisioning solution for EKS clusters,
reserving Cluster Autoscaler for legacy/stateful workloads only.

## Summary Rationale

| Factor | Karpenter | Cluster Autoscaler |
|--------|-----------|-------------------|
| **Provisioning speed** | Sub-second (direct EC2 API) | Minutes (ASG + Launch Template) |
| **Node diversity** | Native (GPU, ARM, Spot, On-Demand in same cluster) | Requires multiple node groups per type |
| **Consolidation** | Automatic (bin-packing optimization) | Requires manual node group tuning |
| **Scaling granularity** | Single pod → single instance | Node group level (must launch full ASG) |
| **Pod density** | Higher (no node group constraints) | Lower (limited by node group boundaries) |

## Detailed Analysis

See Repository 2 (`repo-02-eks-platform`) for the full ADR with:
- Cost comparison between Karpenter and Cluster Autoscaler
- Scheduling constraint evaluation
- Spot interruption handling
- Multi-arch support (ARM64 + AMD64)
