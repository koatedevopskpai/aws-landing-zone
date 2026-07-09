# ADR-001: Transit Gateway over VPC Peering for Multi-Account Connectivity

## Status

Accepted (2026-07-02)

## Context

SecondWave operates a multi-account AWS Organizations structure with:
- 1 shared-services account (logging, networking, security)
- 3 workload accounts (dev, staging, prod)

The platform team needs to connect VPCs across these accounts for:
- Shared services access (logging, monitoring, CI/CD)
- Cross-environment data exchange (prod → shared-services)
- Centralized network inspection and egress

We evaluated two primary approaches: VPC Peering and Transit Gateway.

## Decision

We will use **AWS Transit Gateway** for all cross-account and cross-VPC connectivity.

## Rationale

| Factor | Transit Gateway | VPC Peering |
|--------|----------------|-------------|
| **Topology** | Hub-and-spoke — n attachments | Full mesh — n×(n-1)/2 peerings |
| **Transitive routing** | Native (1 attachment = all VPCs) | Not supported (VPC A can't reach VPC C via B) |
| **Network segmentation** | Route tables isolate environments | No filtering — all subnets exposed |
| **Scalability** | 1000+ attachments per TGW | 125 peerings per VPC |
| **VPN/Direct Connect** | Single attachment for all VPCs | Each VPC needs separate VPN |
| **Cross-account** | AWS RAM share once | Need peering per account pair |
| **Cost (4 VPCs)** | ~$100/mo + data transfer | ~$0 + data transfer (cheaper) |
| **Central inspection** | Support appliance VPC mode | Impossible |

**Critical decider: Future-proofing.** SecondWave may grow to 10+ accounts (new squads, acquisitions). VPC Peering becomes unmanageable at 10 VPCs (45 peerings). Transit Gateway remains a single attachment per VPC.

**Security decider: Environment isolation.** TGW route tables allow us to create security domains (trusted = prod + shared-services, non-production = dev + staging). With VPC Peering, any peering connection exposes the entire VPC.

## Consequences

**Positive:**
- Simplified network topology — single TGW for all routing
- Enables central inspection (firewall, NIDS) in shared-services
- Route tables enforce environment segmentation
- Direct Connect integration for on-premises connectivity

**Negative:**
- Higher base cost (~$66/mo per attachment region) vs VPC Peering (~$0)
- TGW is an additional network hop (adds ~1-2ms latency)
- More complex troubleshooting (need VPC Flow Logs on TGW attachments)

## Implementation

See `modules/transit-gateway/main.tf` for the implementation.

Key design choices:
- Separate route tables for trusted vs non-production environments
- Blackhole routes to prevent non-production → prod traffic
- Appliance mode support for future firewall insertion
- DNS support enabled for cross-account Private Hosted Zones
