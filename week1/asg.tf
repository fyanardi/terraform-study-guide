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
