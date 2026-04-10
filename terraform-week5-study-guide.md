# Terraform + AWS: Week 5 Study Guide

## Overview

This week you'll deploy a containerized application on ECS Fargate — the most common container orchestration pattern on AWS. You'll build a complete setup with an ECS cluster, task definitions, services, ALB integration, IAM roles, and CloudWatch logging. This is one of the most practical and interview-relevant AWS patterns to know.

---

## Day 1–2: ECS Cluster & Task Definition

Set up the ECS foundation with a cluster and your first task definition.

### Resources to Build

1. **`aws_ecs_cluster`** — Create the cluster with Container Insights enabled:

```hcl
resource "aws_ecs_cluster" "main" {
  name = "${var.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}
```

2. **`aws_cloudwatch_log_group`** — Create a log group for container logs:

```hcl
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.environment}/app"
  retention_in_days = 30
}
```

3. **`aws_ecs_task_definition`** — Define your container. Start with a simple nginx image:

```hcl
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.environment}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "nginx:latest"
      essential = true
      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}
```

4. **IAM Roles** — ECS needs two separate roles:

   - **Execution role** (`ecs_execution`): Used by the ECS agent to pull images from ECR and write logs. Attach `AmazonECSTaskExecutionRolePolicy`.
   - **Task role** (`ecs_task`): Used by your application code to access AWS services (S3, DynamoDB, Secrets Manager, etc.). Start with no policies and add as needed.

```hcl
# Execution role
resource "aws_iam_role" "ecs_execution" {
  name = "${var.environment}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role (add policies as your app needs them)
resource "aws_iam_role" "ecs_task" {
  name = "${var.environment}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}
```

### Exercises

- Run `terraform apply` and inspect the task definition in the ECS console. Understand the difference between task definition and running task.
- Try changing the container image to `httpd:latest` and run `terraform plan` — notice a new revision of the task definition is created.
- Look at the IAM roles in the console. Understand why there are two separate roles.

---

## Day 3: ECS Service + ALB

Create an ECS service that runs your task and connect it to a load balancer.

### Resources to Build

1. **`aws_security_group`** — Create one for the ALB (allow 80/443 from anywhere) and one for the ECS tasks (allow traffic only from the ALB security group).

2. **`aws_lb`** — Application Load Balancer in public subnets (reuse the pattern from Week 1).

3. **`aws_lb_target_group`** — Must use `target_type = "ip"` for Fargate:

```hcl
resource "aws_lb_target_group" "app" {
  name        = "${var.environment}-app"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"    # Required for Fargate

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }
}
```

4. **`aws_lb_listener`** — Forward port 80 to the target group.

5. **`aws_ecs_service`** — Run the task definition as a service:

```hcl
resource "aws_ecs_service" "app" {
  name            = "${var.environment}-app"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.http]
}
```

### Exercises

- Hit the ALB DNS in your browser — you should see the nginx welcome page.
- Go to the ECS console and watch the tasks start. Check the "Logs" tab to see container output.
- Stop a task manually in the console — watch the service automatically replace it (similar to ASG behavior).
- Change `desired_count` to 3, apply, and watch the new task spin up.

---

## Day 4: ECR & Custom Container Image

Push your own Docker image to ECR and deploy it on ECS.

### Resources to Build

1. **`aws_ecr_repository`** — Create a repository for your app image:

```hcl
resource "aws_ecr_repository" "app" {
  name                 = "${var.environment}-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = var.environment != "prod"

  image_scanning_configuration {
    scan_on_push = true
  }
}
```

2. **`aws_ecr_lifecycle_policy`** — Keep only the last 10 images to save storage costs:

```hcl
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
```

### Build and Push a Docker Image

Create a simple Dockerfile:

```dockerfile
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
```

Push it to ECR:

```bash
# Authenticate Docker to ECR
aws ecr get-login-password --region ap-southeast-1 --profile terraform | \
  docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com

# Build and push
docker build -t my-app .
docker tag my-app:latest <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/dev-app:latest
docker push <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/dev-app:latest
```

Update your task definition to use the ECR image instead of `nginx:latest`.

### Exercises

- Deploy the custom image and verify it serves your custom `index.html`.
- Push a new version of the image with a different tag, update the task definition, and apply. Watch ECS perform a rolling deployment.
- Check the ECR console for vulnerability scan results.

---

## Day 5: Auto Scaling for ECS

Add auto scaling to your ECS service so it responds to load.

### Resources to Build

1. **`aws_appautoscaling_target`** — Register the ECS service as a scalable target:

```hcl
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = 6
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}
```

2. **`aws_appautoscaling_policy`** — Target tracking on CPU:

```hcl
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.environment}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
```

3. **Optionally add a second policy** for request count per target:

```hcl
resource "aws_appautoscaling_policy" "requests" {
  name               = "${var.environment}-request-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }
    target_value       = 1000
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
```

### Exercises

- Apply the scaling policies and check the CloudWatch alarms that are automatically created.
- Use a load testing tool like `hey` or `ab` to generate traffic against the ALB. Watch ECS scale out.
- Compare ECS auto scaling with the EC2 ASG auto scaling from Week 1 — notice the similarities in concept.

---

## Day 6–7: Clean Up & Reflect

### Tasks

1. **Create an ECS module** — Refactor your ECS resources into a reusable module with inputs for image, CPU/memory, scaling settings, and environment.
2. **Environment variables** — Add `environment` block to your container definition to pass configuration (database URL, API keys from Secrets Manager).
3. **Test full destroy and re-apply** — ECS resources can be tricky with dependencies. Fix any ordering issues.
4. **Write a README** documenting your ECS architecture.

### Bonus Challenges

- Add a second container to the task definition as a sidecar (e.g., a log router or reverse proxy).
- Connect your ECS task to the RDS database from Week 4 by passing the Secrets Manager ARN and adding an IAM policy to the task role.
- Try ECS Exec (`aws ecs execute-command`) to get a shell inside a running container — useful for debugging.
- Add a deployment circuit breaker to the ECS service:

```hcl
deployment_circuit_breaker {
  enable   = true
  rollback = true
}
```

---

## Suggested File Structure (End of Week)

```
week5-ecs/
├── main.tf              # Provider config, locals
├── variables.tf
├── terraform.tfvars
├── outputs.tf
├── vpc.tf               # Or reference VPC module
├── ecs-cluster.tf       # Cluster, log group
├── ecs-task.tf          # Task definition, IAM roles
├── ecs-service.tf       # Service, auto scaling
├── alb.tf               # ALB, target group, listener
├── ecr.tf               # ECR repository
├── security-groups.tf   # ALB and ECS task security groups
├── .gitignore
└── README.md
```

---

## Key Concepts This Week

| Concept | Why It Matters |
|---|---|
| Fargate launch type | No EC2 instances to manage — true serverless containers |
| Execution role vs task role | Separation of concerns: ECS agent vs your application |
| `awsvpc` network mode | Each task gets its own ENI and private IP |
| `target_type = "ip"` | Required for Fargate because containers have dynamic IPs |
| ECR lifecycle policies | Prevents unbounded storage costs from old images |
| ECS auto scaling | Independent from EC2 auto scaling — scales containers, not hosts |
| Rolling deployments | ECS replaces tasks gradually with new task definition revisions |
| Deployment circuit breaker | Automatically rolls back if new tasks keep failing |
