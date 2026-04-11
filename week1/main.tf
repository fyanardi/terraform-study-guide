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

  default_tags {
    tags = {
      Environment = var.environment
    }
  }
}

locals {
  prefix = "${var.project}-${var.environment}"
}

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

resource "aws_security_group" "web" {
  name        = "${local.prefix}-web-security-group"
  description = "Security group for incoming HTTP/HTTPS and SSH"
  vpc_id      = aws_vpc.main.id

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

resource "aws_security_group" "app" {
  name        = "${local.prefix}-app-security-group"
  description = "Security group for applications"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "Inbound from Web security group"
    from_port = 0
    to_port = 0
    protocol = "-1"
    security_groups = [aws_security_group.web.id]
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

resource "aws_key_pair" "personal" {
  key_name = "personal-key-pair"
  public_key = file(var.public_key_location)
}

resource "aws_launch_template" "server" {
  image_id               = var.ec2_ami_id
  instance_type          = var.ec2_instance_size
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = aws_key_pair.personal.key_name

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      delete_on_termination = var.disk.delete_on_termination
      encrypted             = var.disk.encrypted
      volume_size           = var.disk.volume_size
      volume_type           = var.disk.volume_type
    }
  }

  user_data = base64encode(<<-EOF
      #!/bin/bash
      sudo dnf update -y
      sudo dnf install nginx -y
      sudo echo "Hello from $(hostname)" > /usr/share/nginx/html/index.html
      sudo systemctl start nginx
      sudo systemctl enable nginx
    EOF
  )
}

# The Application Load Balancer
resource "aws_lb" "main" {
  name               = "${local.prefix}-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "${local.prefix}-lb"
  }
}

resource "aws_lb_target_group" "main" {
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id

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

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

resource "aws_autoscaling_group" "servers" {
  name                  = "${local.prefix}-autoscaling-group"
  desired_capacity      = 2
  max_size              = 4
  min_size              = 2
  health_check_type     = "ELB"
  termination_policies  = ["OldestInstance"]
  vpc_zone_identifier   = aws_subnet.private[*].id
  target_group_arns     = [aws_lb_target_group.main.arn]

  launch_template {
    id      = aws_launch_template.server.id
    version = "$Latest"
  }
}

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                  = "${local.prefix}-autoscaling-policy"
  autoscaling_group_name = aws_autoscaling_group.servers.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
  }
}
