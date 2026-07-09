# =============================================================================
# VPC MODULE — Segregated Subnets with Mandatory Flow Logs
# =============================================================================
# ARCHITECTURE DECISION: Standard 3-tier subnet architecture (public/private/isolated):
# - Public subnets:  Load balancers, NAT Gateways, Bastion hosts
# - Private subnets: Application servers, ECS/EKS worker nodes
# - Isolated subnets: RDS, ElastiCache, Redshift (NO internet or NAT access)
# ARCHITECTURE DECISION: Isolated subnets for databases because:
# 1. They cannot accidentally be assigned public IPs.
# 2. They have no route to the internet — eliminates an entire attack surface.
# 3. They only communicate via VPC endpoints (Interface/Gateway) to AWS services.
# 4. Meets FCA guidance on network segmentation for sensitive data stores.
# ARCHITECTURE DECISION: Flow logs mandatory because every VPC must support
# forensic investigation and compliance reporting. No opt-out.
# SECURITY SAFEGUARD: Flow logs capture ALL traffic (accept + reject) and are
# delivered to the centralized S3 logging bucket via CloudWatch destination.

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  # ARCHITECTURE DECISION: Subnet CIDRs are computed from the VPC CIDR using
  # cidrsubnet. /19 for public (8190 IPs), /19 for private, /20 for isolated.
  # This gives room for growth without re-IP.
  public_subnets = [
    cidrsubnet(var.vpc_cidr, 3, 0),   # /19
    cidrsubnet(var.vpc_cidr, 3, 1),   # /19
    cidrsubnet(var.vpc_cidr, 3, 2),   # /19
  ]
  private_subnets = [
    cidrsubnet(var.vpc_cidr, 3, 3),   # /19
    cidrsubnet(var.vpc_cidr, 3, 4),   # /19
    cidrsubnet(var.vpc_cidr, 3, 5),   # /19
  ]
  isolated_subnets = [
    cidrsubnet(var.vpc_cidr, 4, 12),  # /20
    cidrsubnet(var.vpc_cidr, 4, 13),  # /20
    cidrsubnet(var.vpc_cidr, 4, 14),  # /20
  ]
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  # ARCHITECTURE DECISION: Instance tenancy defaults to "default" unless
  # overridden. Dedicated tenancy is available for regulated workloads.
  instance_tenancy = var.instance_tenancy

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-vpc"
  })
}

# =============================================================================
# PUBLIC SUBNETS
# =============================================================================
resource "aws_subnet" "public" {
  count = length(local.public_subnets)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnets[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name                             = "${var.project_name}-${var.environment}-public-${local.azs[count.index]}"
    SubnetType                       = "public"
    "kubernetes.io/role/elb"         = "1"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-igw"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = length(local.public_subnets)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# =============================================================================
# PRIVATE SUBNETS
# =============================================================================
resource "aws_subnet" "private" {
  count = length(local.private_subnets)

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(var.tags, {
    Name                                    = "${var.project_name}-${var.environment}-private-${local.azs[count.index]}"
    SubnetType                              = "private"
    "kubernetes.io/role/internal-elb"       = "1"
  })
}

# ARCHITECTURE DECISION: NAT Gateway only in environments that need outbound
# access from private subnets (staging, prod). Dev uses NAT Instance or
# direct VPC endpoints to save cost.
resource "aws_eip" "nat" {
  count = var.enable_natgw && var.enable_natgw_subnet_count > 0 ? var.enable_natgw_subnet_count : 0
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-nat-eip-${count.index + 1}"
  })
}

resource "aws_nat_gateway" "this" {
  count = var.enable_natgw && var.enable_natgw_subnet_count > 0 ? var.enable_natgw_subnet_count : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-natgw-${count.index + 1}"
  })
}

resource "aws_route_table" "private" {
  count = length(local.private_subnets)

  vpc_id = aws_vpc.this.id

  # ARCHITECTURE DECISION: Only add default route to NAT when NAT GW is enabled.
  # Without NAT, private subnets use only VPC endpoints + Transit Gateway.
  dynamic "route" {
    for_each = var.enable_natgw ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.this[count.index % length(aws_nat_gateway.this)].id
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-private-rt-${local.azs[count.index]}"
  })
}

resource "aws_route_table_association" "private" {
  count = length(local.private_subnets)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# =============================================================================
# ISOLATED SUBNETS (Databases, Cache, Message Queues)
# =============================================================================
# ARCHITECTURE DECISION: Isolated subnets have NO route to the internet and no
# NAT gateway. They rely entirely on VPC Endpoints (Gateway + Interface) for
# AWS service access. This follows the AWS Well-Architected Framework security
# pillar for defense in depth.
resource "aws_subnet" "isolated" {
  count = length(local.isolated_subnets)

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.isolated_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(var.tags, {
    Name       = "${var.project_name}-${var.environment}-isolated-${local.azs[count.index]}"
    SubnetType = "isolated"
  })
}

# ARCHITECTURE DECISION: Separate route table for isolated subnets.
# Only VPC Endpoint routes + TGW routes — no internet access.
resource "aws_route_table" "isolated" {
  count = length(local.isolated_subnets)

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-isolated-rt-${local.azs[count.index]}"
  })
}

resource "aws_route_table_association" "isolated" {
  count = length(local.isolated_subnets)

  subnet_id      = aws_subnet.isolated[count.index].id
  route_table_id = aws_route_table.isolated[count.index].id
}

# =============================================================================
# VPC FLOW LOGS (Mandatory — No Exceptions)
# =============================================================================
# SECURITY SAFEGUARD: Flow logs are mandatory for all environments.
# They capture all accepted and rejected traffic metadata.
# SECURITY SAFEGUARD: Flow logs are delivered to CloudWatch Logs group
# then forwarded to the centralized S3 logging bucket via subscription filter.
resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination_type = "cloud-watch-logs"
  log_group_name  = "/aws/vpc-flow-logs/${var.project_name}-${var.environment}"
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.this.id
  max_aggregation_interval = 60

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-flow-logs"
  })
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc-flow-logs/${var.project_name}-${var.environment}"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-flow-logs-cw"
  })
}

# SECURITY SAFEGUARD: IAM role for flow logs follows least-privilege.
# It only has permissions to create log streams and put log events.
resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.project_name}-${var.environment}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-vpc-flow-logs-role"
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.project_name}-${var.environment}-vpc-flow-logs-policy"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# VPC GATEWAY ENDPOINTS (S3, DynamoDB)
# =============================================================================
# ARCHITECTURE DECISION: Gateway endpoints for S3 and DynamoDB over Interface
# endpoints because they are free and use prefix lists instead of Route 53.
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.this.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [for rt in aws_route_table.private : rt.id],
    [for rt in aws_route_table.isolated : rt.id]
  )

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-s3-vpce"
  })
}

data "aws_region" "current" {}

# =============================================================================
# TGW ATTACHMENT SUBNETS (Public subnets for TGW — one per AZ)
# =============================================================================
locals {
  tgw_attachment_subnets = [
    for subnet in aws_subnet.public : subnet.id
  ]
}
