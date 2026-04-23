resource "aws_vpc" "main" {
  cidr_block = var.cidr_block

  tags = {
    Name = "${local.prefix}-vpc"
  }
}

resource "aws_subnet" "public" {
  count             = var.public_subnet_count
  vpc_id            = aws_vpc.main.id
  # CIDR blocks for public subnets start after the public subnet
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, var.private_subnet_count + count.index)
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${local.prefix}-public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = var.private_subnet_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${local.prefix}-private-subnet-${count.index + 1}"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.prefix}-internet-gateway"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.prefix}-public-route-table"
  }
}

resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.prefix}-private-route-table"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_eip" "eip" {
  domain = "vpc"

  tags = {
    Name = "${local.prefix}-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${local.prefix}-nat-gateway"
  }
}

resource "aws_route" "nat_gateway_route" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id

  depends_on = [aws_eip.eip]
}
