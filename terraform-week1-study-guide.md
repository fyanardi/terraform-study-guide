# Terraform + AWS: Week 1 Study Guide

## Overview

This week focuses on building a multi-AZ VPC and deploying EC2 instances behind a load balancer with auto scaling. By the end of the week, you'll have a production-style VPC with a load-balanced, auto-scaling web tier — the backbone of most AWS architectures.

---

## IAM Setup (Before You Start)

Create a dedicated IAM user for Terraform rather than using your root or daily-use account.

1. In the AWS Console, create an IAM user (e.g., `terraform-admin`) with **programmatic access only** (no console login).
2. Attach the `AdministratorAccess` policy for learning purposes. You'll scope this down later.
3. Configure the AWS CLI with a named profile:

```bash
aws configure --profile terraform
# Enter access key, secret key, region (ap-southeast-1)
```

4. Reference the profile in your Terraform provider:

```hcl
provider "aws" {
  region  = "ap-southeast-1"
  profile = "terraform"
}
```

> **Important:** Never hardcode `access_key` and `secret_key` in `.tf` files. Add `*.tfvars` and `.terraform/` to your `.gitignore` from day one.

---

## Day 1–2: VPC Foundation

Start a new project directory and build a VPC from scratch — no modules yet, write every resource manually so you understand what's happening.

### Resources to Build (in order)

1. **`aws_vpc`** — CIDR block like `10.0.0.0/16`
2. **`aws_subnet`** — Create 2 public and 2 private subnets across two AZs (e.g., `ap-southeast-1a` and `ap-southeast-1b`). Use the `cidrsubnet()` function instead of hardcoding CIDR blocks — this is a great early habit.
3. **`aws_internet_gateway`** — Attach to the VPC.
4. **`aws_nat_gateway` + `aws_eip`** — Place in a public subnet so private subnets can reach the internet.
5. **`aws_route_table` + `aws_route_table_association`** — One route table for public subnets (route to IGW), one for private subnets (route to NAT GW).

### Exercises

- Run `terraform plan` and read every line carefully. Understand what "known after apply" means.
- Run `terraform apply`, then go to the AWS Console and visually verify everything in the VPC dashboard.
- Try changing a subnet CIDR and observe what Terraform wants to do (destroy and recreate). This teaches you about immutable vs mutable attributes.

---

## Day 3: Security Groups & Variables

Add security groups and refactor hardcoded values into variables.

### Tasks

1. Create a `variables.tf` with inputs for VPC CIDR, environment name, number of AZs, and allowed SSH CIDR.
2. Create a `terraform.tfvars` for your dev environment values.
3. Add `aws_security_group` resources:
   - **Web tier SG:** Allow 80/443 from anywhere, SSH from your IP only.
   - **App tier SG:** Allow traffic only from the web security group.
4. Create an `outputs.tf` that exports VPC ID, subnet IDs, and security group IDs.

### Exercises

- Use `terraform console` to experiment with functions like `cidrsubnet("10.0.0.0/16", 8, 0)` and `formatlist()`.
- Add a `locals` block to compute things like name prefixes: `"${var.environment}-${var.project}"`.
- Try adding validation to a variable, e.g., `environment` must be one of `["dev", "staging", "prod"]`.

---

## Day 4: EC2 + ALB

Deploy a basic web server behind a load balancer.

### Resources to Build

1. **`aws_instance`** — Launch an EC2 in a public subnet with a `user_data` script that installs and starts nginx. Use Amazon Linux 2023 AMI.
2. **`aws_lb`** (Application Load Balancer) — Place in public subnets.
3. **`aws_lb_target_group`** — Health check on port 80, path `/`.
4. **`aws_lb_listener`** — Listen on port 80, forward to the target group.
5. **`aws_lb_target_group_attachment`** — Register your EC2 instance.

### User Data Script

```bash
#!/bin/bash
yum install -y nginx
systemctl start nginx
echo "Hello from $(hostname)" > /usr/share/nginx/html/index.html
```

### Exercises

- Hit the ALB DNS name in your browser — you should see the nginx page.
- Intentionally break the health check (change the path to `/bad`) and observe what happens in the console.
- Use `terraform output` to print the ALB DNS — practice making outputs useful.

---

## Day 5: Auto Scaling Group

Replace your single EC2 instance with an ASG so you have self-healing, scalable infrastructure.

### Resources to Build

1. **`aws_launch_template`** — Move your AMI, instance type, security group, and `user_data` here. This replaces the standalone `aws_instance`.
2. **`aws_autoscaling_group`** — Min 2, max 4, desired 2. Place in private subnets. Attach to the ALB target group.
3. **`aws_autoscaling_policy`** — Create a target tracking policy for average CPU at 60%.
4. **Remove** the old `aws_instance` and `aws_lb_target_group_attachment` — the ASG handles registration automatically.

### Exercises

- After applying, terminate one instance manually in the console. Watch the ASG replace it automatically.
- SSH into an instance (via a bastion or Session Manager) and run `stress --cpu 2` to trigger scaling. Watch new instances appear.
- Run `terraform plan` after the ASG has scaled out — notice Terraform doesn't care about the current instance count because it only manages desired capacity.

---

## Day 6–7: Clean Up & Reflect

### Tasks

1. **Draw an architecture diagram** of what you built (even a rough sketch). Label every resource and how they connect.
2. **Organize your code** — split into `main.tf`, `variables.tf`, `outputs.tf`, `vpc.tf`, `alb.tf`, `asg.tf`. There's no single right structure, but get comfortable with separation.
3. **Run `terraform destroy`** and then `terraform apply` from zero. If it works cleanly, your code is solid. If not, fix what breaks.
4. **Write a README** — what you built, what you learned, what surprised you.

### Bonus Challenges

- Add a `data` source to look up the latest Amazon Linux AMI dynamically instead of hardcoding it.
- Add tags to every resource using `default_tags` in the provider block.
- Try `terraform state list` and `terraform state show <resource>` to explore your state file.

---

## Suggested File Structure (End of Week)

```
week1-project/
├── main.tf            # Provider config, locals
├── variables.tf       # All input variables
├── terraform.tfvars   # Dev environment values
├── outputs.tf         # Exported values
├── vpc.tf             # VPC, subnets, IGW, NAT, route tables
├── security.tf        # Security groups
├── alb.tf             # ALB, target group, listener
├── asg.tf             # Launch template, ASG, scaling policy
├── .gitignore         # *.tfvars, .terraform/, *.tfstate*
└── README.md          # What you built and learned
```

---

## Key Commands Reference

| Command | Purpose |
|---|---|
| `terraform init` | Initialize working directory, download providers |
| `terraform plan` | Preview changes without applying |
| `terraform apply` | Apply changes to infrastructure |
| `terraform destroy` | Tear down all managed resources |
| `terraform fmt` | Auto-format your `.tf` files |
| `terraform validate` | Check syntax and configuration errors |
| `terraform console` | Interactive console to test expressions |
| `terraform state list` | List all resources in state |
| `terraform state show <resource>` | Show details of a specific resource |
| `terraform output` | Display output values |
