# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
resource "aws_vpc" "olive_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "olive-vpc" }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# ---------------------------------------------------------------------------
# Public subnets (for the NAT gateway + internet-facing resources)
# ---------------------------------------------------------------------------
resource "aws_subnet" "olive_public_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.olive_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "olive-public-subnet-${count.index}" }
}

# ---------------------------------------------------------------------------
# Private subnets (ECS tasks, RDS, Redshift live here - no direct internet)
# ---------------------------------------------------------------------------
resource "aws_subnet" "olive_private_subnet" {
  count             = 2
  vpc_id            = aws_vpc.olive_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "olive-private-subnet-${count.index}" }
}

# ---------------------------------------------------------------------------
# Internet Gateway + public routing
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "olive_igw" {
  vpc_id = aws_vpc.olive_vpc.id
  tags = { Name = "olive-igw" }
}

resource "aws_route_table" "olive_public_rt" {
  vpc_id = aws_vpc.olive_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.olive_igw.id
  }

  tags = { Name = "olive-public-rt" }
}

resource "aws_route_table_association" "olive_public_rt_assoc" {
  count          = 2
  subnet_id      = aws_subnet.olive_public_subnet[count.index].id
  route_table_id = aws_route_table.olive_public_rt.id
}

# ---------------------------------------------------------------------------
# NAT Gateway + private routing (lets private subnets reach the internet
# outbound only - e.g. to pull container images, call AWS APIs)
# ---------------------------------------------------------------------------
resource "aws_eip" "olive_nat_eip" {
  domain = "vpc"
  tags   = { Name = "olive-nat-eip" }
}

resource "aws_nat_gateway" "olive_nat_gw" {
  allocation_id = aws_eip.olive_nat_eip.id
  subnet_id     = aws_subnet.olive_public_subnet[0].id
  tags          = { Name = "olive-nat-gw" }

  depends_on = [aws_internet_gateway.olive_igw]
}

resource "aws_route_table" "olive_private_rt" {
  vpc_id = aws_vpc.olive_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.olive_nat_gw.id
  }

  tags = { Name = "olive-private-rt" }
}

resource "aws_route_table_association" "olive_private_rt_assoc" {
  count          = 2
  subnet_id      = aws_subnet.olive_private_subnet[count.index].id
  route_table_id = aws_route_table.olive_private_rt.id
}
