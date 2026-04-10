# Terraform + AWS: Week 4 Study Guide

## Overview

This week you'll add a data tier to your infrastructure with RDS (PostgreSQL) and learn to manage secrets properly with AWS Secrets Manager. You'll also explore Terraform lifecycle rules, data sources, and how to handle sensitive values safely. This is the week where you start dealing with the messy reality of stateful infrastructure.

---

## Day 1–2: RDS PostgreSQL

Deploy a managed PostgreSQL database in your private subnets.

### Resources to Build

1. **`aws_db_subnet_group`** — Group your private subnets so RDS knows where to deploy. Use the private subnet IDs from your VPC module.
2. **`aws_security_group`** — Allow inbound on port 5432 only from your application security group. No public access.
3. **`aws_db_instance`** — Create a PostgreSQL instance with these settings:

```hcl
resource "aws_db_instance" "main" {
  identifier     = "${var.environment}-postgres"
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100    # Enables storage autoscaling

  db_name  = "appdb"
  username = "dbadmin"
  password = var.db_password     # We'll fix this with Secrets Manager next

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  multi_az            = var.environment == "prod" ? true : false
  skip_final_snapshot = var.environment != "prod"

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  tags = {
    Environment = var.environment
  }
}
```

4. **`aws_db_parameter_group`** (optional) — Create a custom parameter group if you want to tune PostgreSQL settings like `log_statement` or `max_connections`.

### Exercises

- Run `terraform apply` and note how long RDS takes to create (~10-15 minutes). This is normal.
- Find the RDS endpoint in `terraform output` and try connecting from an EC2 instance in the same VPC using `psql`.
- Try changing `instance_class` and run `terraform plan` — notice it's an in-place update, not destroy-and-recreate.
- Try changing `engine_version` — observe that some version changes require a reboot or cause downtime.

---

## Day 3: Secrets Manager

Stop passing database passwords as plain-text variables. Use Secrets Manager to generate and store them.

### Resources to Build

1. **`random_password`** — Generate a strong password:

```hcl
resource "random_password" "db" {
  length  = 32
  special = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}
```

2. **`aws_secretsmanager_secret`** — Create the secret container:

```hcl
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.environment}/database/credentials"
  description = "RDS PostgreSQL credentials"
}
```

3. **`aws_secretsmanager_secret_version`** — Store the actual values:

```hcl
resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = aws_db_instance.main.username
    password = random_password.db.result
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = aws_db_instance.main.db_name
  })
}
```

4. **Update `aws_db_instance`** to use the random password:

```hcl
password = random_password.db.result
```

### Exercises

- After applying, go to Secrets Manager in the console and verify the secret is stored correctly.
- Check your state file (`terraform state pull`) — notice the password is stored in plain text in the state. This is why encrypting your state bucket matters.
- Try adding `sensitive = true` to your outputs and observe how Terraform hides them in the CLI.
- Destroy and re-apply — a new random password will be generated. Understand why this is actually a problem for existing databases (it would lock you out).

---

## Day 4: Lifecycle Rules & Protecting Resources

Learn how to prevent Terraform from accidentally destroying critical resources.

### Key Lifecycle Rules

```hcl
resource "aws_db_instance" "main" {
  # ... configuration ...

  lifecycle {
    prevent_destroy = true    # Terraform will refuse to destroy this
  }
}
```

```hcl
resource "aws_db_instance" "main" {
  # ... configuration ...

  lifecycle {
    ignore_changes = [password]  # Don't track password changes after creation
  }
}
```

```hcl
resource "aws_instance" "example" {
  # ... configuration ...

  lifecycle {
    create_before_destroy = true  # Create replacement before destroying old one
  }
}
```

### Tasks

1. Add `prevent_destroy = true` to your RDS instance and your S3 state bucket (from Week 2). Try running `terraform destroy` and observe the error.
2. Add `ignore_changes = [password]` to the RDS instance. This lets you rotate passwords outside of Terraform without causing drift.
3. Understand `create_before_destroy` — add it to your launch template and see how it affects replacement behavior.

### Exercises

- Try all three lifecycle rules. Understand when each is appropriate.
- With `prevent_destroy` on, try `terraform destroy` and read the error message carefully.
- Remove `prevent_destroy`, destroy the RDS instance, then add it back and re-apply. Notice the long wait time — this is why you protect databases.

---

## Day 5: Data Sources & Dynamic AMI Lookup

Learn to use `data` sources to look up existing resources and information.

### Common Data Sources

```hcl
# Look up the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Look up available AZs in the current region
data "aws_availability_zones" "available" {
  state = "available"
}

# Look up your current AWS account ID
data "aws_caller_identity" "current" {}

# Look up the current region
data "aws_region" "current" {}
```

### Tasks

1. Replace any hardcoded AMI IDs in your launch template with `data.aws_ami.amazon_linux.id`.
2. Replace hardcoded AZ names with `data.aws_availability_zones.available.names`.
3. Use `data.aws_caller_identity.current.account_id` in your IAM policies or resource names.
4. Refactor your modules to use data sources instead of hardcoded values wherever possible.

### Exercises

- Run `terraform console` and evaluate `data.aws_ami.amazon_linux` to see all the attributes available.
- Change the AMI filter to find Ubuntu instead of Amazon Linux — observe how the data source returns different results.
- Use `data.aws_availability_zones` with `for_each` to create subnets dynamically across all available AZs.

---

## Day 6–7: Clean Up & Reflect

### Tasks

1. **Review your state file security** — Is your S3 bucket encrypted? Is public access blocked? Is versioning enabled?
2. **Audit sensitive values** — Run `terraform state pull | grep -i password` to see what's exposed in state. Mark sensitive outputs.
3. **Test full lifecycle** — Destroy and re-apply everything (remove `prevent_destroy` temporarily). Fix any ordering issues.
4. **Update your README** — Document the database setup, how credentials are managed, and any lifecycle rules.

### Bonus Challenges

- Use `aws_rds_cluster` instead of `aws_db_instance` to create an Aurora PostgreSQL cluster.
- Add `aws_secretsmanager_secret_rotation` to automatically rotate database credentials on a schedule.
- Create a `data` source that reads a secret from Secrets Manager in a different project (simulating how an application would consume the credentials).
- Add `moved` blocks to practice renaming resources without destroying them.

---

## Key Concepts This Week

| Concept | Why It Matters |
|---|---|
| RDS in private subnets | Databases should never be publicly accessible |
| Secrets Manager | Centralized, auditable secret storage with rotation support |
| `random_password` provider | Generate secrets at apply time, not in tfvars |
| `prevent_destroy` | Safety net for stateful resources like databases |
| `ignore_changes` | Let external processes modify attributes without drift |
| `create_before_destroy` | Zero-downtime replacements for stateless resources |
| Data sources | Look up dynamic values instead of hardcoding |
| Sensitive state | State files contain secrets — encrypt and restrict access |
