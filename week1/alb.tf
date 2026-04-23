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
