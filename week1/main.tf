terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.40.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = "terraform"
}

locals {
  prefix = "${var.project}-${var.environment}"
}

resource "aws_vpc" "vpc" {
  cidr_block = var.cidr_block

  tags = {
    Name = "${local.prefix}-vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  count             = var.public_subnet_count
  vpc_id            = aws_vpc.vpc.id
  # CIDR blocks for public subnets start after the public subnet
  cidr_block        = cidrsubnet(aws_vpc.vpc.cidr_block, 8, var.private_subnet_count + count.index)
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${local.prefix}-public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnet" {
  count             = var.private_subnet_count
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(aws_vpc.vpc.cidr_block, 8, count.index)
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${local.prefix}-private-subnet-${count.index + 1}"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${local.prefix}-internet-gateway"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${local.prefix}-public-route-table"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}

resource "aws_route_table_association" "public_subnet_association" {
  count          = length(aws_subnet.public_subnet)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${local.prefix}-private-route-table"
  }
}

resource "aws_route_table_association" "private_subnet_association" {
  count          = length(aws_subnet.private_subnet)
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_eip" "eip" {
  domain = "vpc"

  tags = {
    Name = "${local.prefix}-eip"
  }
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.public_subnet[0].id

  tags = {
    Name = "${local.prefix}-nat-gateway"
  }
}

resource "aws_route" "nat_gateway_route" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway.id

  depends_on = [aws_eip.eip]
}

resource "aws_security_group" "web_security_group" {
  name = "web_security_group"
  description = "Security group for incoming HTTP/HTTPS and SSH"
  vpc_id = aws_vpc.vpc.id

  ingress {
    description = "Inbound SSH"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = var.allowed_ssh_cidr_blocks
  }

  ingress {
    description = "Inbound HTTP"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Inbound HTTPS"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${local.prefix}-web-security-group"
  }
}

resource "aws_security_group" "app_security_group" {
  name = "app_security_group"
  description = "Security group for applications"
  vpc_id = aws_vpc.vpc.id

  ingress {
    description = "Inbound from Web security group"
    from_port = 0
    to_port = 0
    protocol = "-1"
    security_groups = [aws_security_group.web_security_group.id]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${local.prefix}-app-security-group"
  }
}

resource "aws_key_pair" "key_pair" {
  key_name = "personal-key-pair"
  public_key = file(var.public_key_location)
}

resource "aws_instance" "ec2" {
  ami                    = var.ec2_ami_id
  instance_type          = var.ec2_instance_size
  vpc_security_group_ids = [aws_security_group.web_security_group.id]
  subnet_id              = aws_subnet.public_subnet[0].id
  key_name               = aws_key_pair.key_pair.key_name
  associate_public_ip_address = var.ec2_associate_public_ip_address
  root_block_device {
    delete_on_termination = var.disk.delete_on_termination
    encrypted             = var.disk.encrypted
    volume_size           = var.disk.volume_size
    volume_type           = var.disk.volume_type
  }
  tags = {
    Name = "${local.prefix}-ec2"
  }

  user_data = <<-EOF
      #!/bin/bash
      sudo dnf update -y
      sudo dnf install nginx -y
      sudo echo "Hello from $(hostname)" > /usr/share/nginx/html/index.html
      sudo systemctl start nginx
      sudo systemctl enable nginx
    EOF
}

# The Application Load Balancer
resource "aws_lb" "lb" {
  name               = "${local.prefix}-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_security_group.id]
  subnets            = aws_subnet.public_subnet[*].id

  tags = {
    Name = "${local.prefix}-lb"
  }
}

resource "aws_lb_target_group" "lb_tg" {
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id

  # Health check configuration
  health_check {
    enabled             = true
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  # Deregistration delay - how long to wait before removing targets
  deregistration_delay = 30

  tags = {
    Name = "${local.prefix}-lb-tg"
  }
}

resource "aws_lb_listener" "lb_listener" {
  load_balancer_arn = aws_lb.lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lb_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "lb_tg_attachment" {
  target_group_arn = aws_lb_target_group.lb_tg.arn
  target_id        = aws_instance.ec2.id
  port             = 80
}
