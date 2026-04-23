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
