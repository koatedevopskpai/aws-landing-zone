# =============================================================================
# TRANSIT GATEWAY MODULE — Centralised Network Hub
# =============================================================================
# ARCHITECTURE DECISION: Transit Gateway over VPC Peering because:
# 1. TGW supports transitive routing — a single attachment connects all VPCs.
#    VPC Peering requires n*(n-1)/2 connections for full mesh.
# 2. TGW route tables isolate environments — prod cannot route to dev unless
#    explicitly propagated. VPC Peering cannot filter traffic between peerings.
# 3. TGW supports 1000+ VPC attachments; VPC Peering max is 125 per VPC.
# 4. TGW integrates with Direct Connect Gateway, VPN, and Network Manager.
# 5. TGW attachments can span accounts without cross-account peering limits.
#
# For full decision record, see docs/ADR/001-transit-gateway-over-vpc-peering.md
#
# SECURITY SAFEGUARD: Separate TGW route tables per environment to enforce
# network segmentation. Production route tables do NOT propagate dev routes.
# SECURITY SAFEGUARD: Default route table is empty — routes must be explicitly
# propagated. This prevents accidental connectivity.

locals {
  # ARCHITECTURE DECISION: Segment environments into security domains.
  # Production and shared-services share one route table (trusted).
  # Dev and staging share another (non-production).
  # A separate route table isolates prod from lower environments.
  security_domains = {
    trusted         = ["shared-services", "prod"]
    non-production  = ["dev", "staging"]
  }
}

resource "aws_ec2_transit_gateway" "this" {
  description = "${var.project_name}-${var.environment}-tgw"
  amazon_side_asn = var.amazon_side_asn

  # ARCHITECTURE DECISION: Default route table association = disabled.
  # Each attachment is manually associated with an environment-specific
  # route table to enforce segmentation.
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"

  # SECURITY SAFEGUARD: DNS support allows resolution of private hosted zones
  # across accounts via TGW.
  dns_support = "enable"

  # SECURITY SAFEGUARD: VPN ECMP support for multiple VPN tunnels.
  vpn_ecmp_support = "enable"

  # SECURITY SAFEGUARD: Auto-accept shared attachments from other accounts.
  # Requires explicit share via AWS RAM.
  auto_accept_shared_attachments = "enable"

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-tgw"
  })
}

# =============================================================================
# TGW ROUTE TABLES (Per Security Domain)
# =============================================================================
resource "aws_ec2_transit_gateway_route_table" "trusted" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-tgw-rt-trusted"
  })
}

resource "aws_ec2_transit_gateway_route_table" "non_production" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-tgw-rt-non-production"
  })
}

# =============================================================================
# VPC ATTACHMENTS
# =============================================================================
# ARCHITECTURE DECISION: Each VPC gets a dedicated attachment. Cross-account
# attachments use AWS Resource Access Manager (RAM) to share the TGW.
# The attachment is created in the VPC owner's account and associated with
# the appropriate TGW route table.
resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = var.vpc_attachments

  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = each.value.vpc_id
  subnet_ids         = each.value.subnet_ids

  # SECURITY SAFEGUARD: DNS support enables cross-account DNS resolution.
  # Appliance mode enables symmetric routing for firewalls/NIDS.
  dns_support  = true
  appliance_mode_support = "enable"

  tags = merge(var.tags, {
    Name = "${var.project_name}-tgw-attach-${each.key}"
    Environment = each.key
  })
}

# =============================================================================
# ROUTE TABLE ASSOCIATIONS (Associate each attachment to its domain)
# =============================================================================
resource "aws_ec2_transit_gateway_route_table_association" "trusted" {
  for_each = {
    for env, attach in aws_ec2_transit_gateway_vpc_attachment.this :
    env => attach
    if contains(local.security_domains["trusted"], env)
  }

  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.trusted.id
  transit_gateway_attachment_id  = each.value.id
}

resource "aws_ec2_transit_gateway_route_table_association" "non_production" {
  for_each = {
    for env, attach in aws_ec2_transit_gateway_vpc_attachment.this :
    env => attach
    if contains(local.security_domains["non-production"], env)
  }

  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.non_production.id
  transit_gateway_attachment_id  = each.value.id
}

# =============================================================================
# ROUTE PROPAGATION (Share routes within domain)
# =============================================================================
# ARCHITECTURE DECISION: Routes are propagated within the same security domain.
# This means all VPCs in "trusted" (shared-services + prod) can route to each
# other. Non-production VPCs can route within themselves. No cross-domain routing.
resource "aws_ec2_transit_gateway_route_table_propagation" "trusted" {
  for_each = {
    for env, attach in aws_ec2_transit_gateway_vpc_attachment.this :
    env => attach
    if contains(local.security_domains["trusted"], env)
  }

  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.trusted.id
  transit_gateway_attachment_id  = each.value.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "non_production" {
  for_each = {
    for env, attach in aws_ec2_transit_gateway_vpc_attachment.this :
    env => attach
    if contains(local.security_domains["non-production"], env)
  }

  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.non_production.id
  transit_gateway_attachment_id  = each.value.id
}

# =============================================================================
# BLACKHOLE ROUTES (Network Segmentation Enforcement)
# =============================================================================
# SECURITY SAFEGUARD: Explicit blackhole routes prevent non-production from
# reaching production. Even if a route accidentally propagates, the static
# blackhole route takes priority.
resource "aws_ec2_transit_gateway_route" "non_prod_to_prod_blackhole" {
  for_each = toset(local.security_domains["non-production"])

  destination_cidr_block         = var.vpc_cidrs["prod"]
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.non_production.id
  blackhole                      = true
}

# =============================================================================
# VPC ROUTE TABLE UPDATES (Point VPC routes to TGW)
# =============================================================================
# ARCHITECTURE DECISION: TGW is the default route for all environment-to-environment
# traffic. Per-environment CIDRS get a TGW route. This is done in the VPC module
# via an optional TGW route variable (configured after TGW creation).
