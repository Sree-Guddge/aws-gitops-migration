# modules/network/main.tf
# Creates a VPC with public/private subnets across 3 AZs, route tables,
# NACLs, security groups, NAT gateways, and VPC flow logs.
# AZs are resolved dynamically via data source -- no hardcoded AZ names.
# NOTE: The canonical module path is modules/vpc/. This file is kept for
# backwards compatibility. New references should use modules/vpc/.

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name   = "${var.name}-vpc"
    Region = data.aws_region.current.name
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-igw" })
}

# Public subnets
resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = false # Explicit assignment only

  tags = merge(var.tags, {
    Name = "${var.name}-public-${data.aws_availability_zones.available.names[count.index]}"
    Tier = "public"
  })
}

# Private subnets
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.tags, {
    Name = "${var.name}-private-${data.aws_availability_zones.available.names[count.index]}"
    Tier = "private"
  })
}

# NAT Gateways (one per AZ for HA)
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? length(var.public_subnet_cidrs) : 0
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-nat-eip-${count.index}" })
}

resource "aws_nat_gateway" "this" {
  count         = var.enable_nat_gateway ? length(var.public_subnet_cidrs) : 0
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = merge(var.tags, { Name = "${var.name}-nat-${count.index}" })
  depends_on    = [aws_internet_gateway.this]
}

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = merge(var.tags, { Name = "${var.name}-rt-public" })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route tables (one per AZ)
resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.this.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.this[count.index].id
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-rt-private-${count.index}" })
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Default NACL -- deny all, no ingress/egress rules
resource "aws_default_network_acl" "default" {
  default_network_acl_id = aws_vpc.this.default_network_acl_id
  tags                   = merge(var.tags, { Name = "${var.name}-default-nacl" })
  # No ingress or egress blocks = deny all traffic by default
}

# Default security group -- no rules (deny all)
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-default-sg-deny-all" })
  # No ingress or egress blocks = deny all traffic by default
}

# VPC Flow Logs -- S3 destination (not CloudWatch)
resource "aws_flow_log" "this" {
  count                = var.flow_log_bucket_arn != "" ? 1 : 0
  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  iam_role_arn         = null
  log_destination      = var.flow_log_bucket_arn
  log_destination_type = "s3"

  tags = merge(var.tags, { Name = "${var.name}-flow-logs" })
}
