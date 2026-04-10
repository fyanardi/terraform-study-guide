# Terraform + AWS: Week 3 Study Guide

## Overview

This week is about writing reusable Terraform modules. You'll refactor your Week 1 VPC and compute resources into proper modules, learn how modules communicate through inputs and outputs, and set up a multi-environment structure. Modules are how real teams scale Terraform — without them, you end up copy-pasting hundreds of lines across projects.

---

## Day 1–2: Your First Module — VPC

Take the VPC code from Week 1 and turn it into a reusable module.

### Module Structure

```
modules/
└── vpc/
    ├── main.tf          # VPC, subnets, IGW, NAT, route tables
    ├── variables.tf     # Inputs: CIDR, AZ count, environment, etc.
    ├── outputs.tf       # Outputs: VPC ID, subnet IDs, etc.
    └── README.md        # What this module does, example usage
```

### Variables to Expose

```hcl
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid CIDR block."
  }
}

variable "environment" {
  description = "Environment name"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Must be dev, staging, or prod."
  }
}

variable "az_count" {
  description = "Number of availability zones to use"
  type        = number
  default     = 2
}

variable "enable_nat_gateway" {
  description = "Whether to create a NAT gateway (costs money)"
  type        = bool
  default     = true
}
```

### Outputs to Expose

```hcl
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}
```

### Call the Module

```hcl
module "vpc" {
  source       = "./modules/vpc"
  vpc_cidr     = "10.0.0.0/16"
  environment  = "dev"
  az_count     = 2
}
```

### Exercises

- Run `terraform plan` and notice how resources are now prefixed with `module.vpc.`.
- Try calling the module twice with different names and CIDRs — you just created two VPCs.
- Try accessing a module output: `module.vpc.vpc_id`. Use this in other resources.

---

## Day 3: Compute Module

Create a second module for the ALB + ASG pattern from Week 1.

### Module Structure

```
modules/
└── web_cluster/
    ├── main.tf          # Launch template, ASG, ALB, listener, target group
    ├── variables.tf     # Inputs: VPC ID, subnet IDs, instance type, etc.
    ├── outputs.tf       # Outputs: ALB DNS name, ASG name
    └── README.md
```

### Key Design Decisions

- The module should accept `vpc_id`, `public_subnet_ids`, and `private_subnet_ids` as inputs — it shouldn't create its own VPC.
- Accept `instance_type`, `min_size`, `max_size`, and `desired_capacity` as variables with sensible defaults.
- Accept the `user_data` script as a variable so the module is reusable for different applications.
- Output the ALB DNS name and the ASG name.

### Wire the Modules Together

```hcl
module "vpc" {
  source      = "./modules/vpc"
  environment = "dev"
  az_count    = 2
}

module "web" {
  source             = "./modules/web_cluster"
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  instance_type      = "t3.micro"
  environment        = "dev"
}

output "website_url" {
  value = module.web.alb_dns_name
}
```

### Exercises

- Deploy the full stack using modules. Confirm the ALB serves traffic.
- Change `instance_type` in the module call and observe what Terraform plans (rolling replacement via launch template).
- Try passing an invalid value (e.g., wrong subnet ID) and see how error messages look with modules.

---

## Day 4–5: Multi-Environment Setup

Use your modules to manage dev, staging, and prod environments.

### Option A: Directory-Based (Recommended for Beginners)

```
environments/
├── dev/
│   ├── main.tf          # Calls modules with dev settings
│   ├── terraform.tfvars
│   └── backend.tf       # Remote state with key = "dev/terraform.tfstate"
├── staging/
│   ├── main.tf
│   ├── terraform.tfvars
│   └── backend.tf       # key = "staging/terraform.tfstate"
└── prod/
    ├── main.tf
    ├── terraform.tfvars
    └── backend.tf        # key = "prod/terraform.tfstate"

modules/
├── vpc/
└── web_cluster/
```

Each environment is a separate Terraform root module with its own state file. This is the safest approach — a mistake in dev can never affect prod.

### Option B: Workspaces

```bash
terraform workspace new dev
terraform workspace new staging
terraform workspace new prod
terraform workspace select dev
```

Use `terraform.workspace` in your code:

```hcl
locals {
  env_config = {
    dev     = { instance_type = "t3.micro", min_size = 1, max_size = 2 }
    staging = { instance_type = "t3.small", min_size = 2, max_size = 3 }
    prod    = { instance_type = "t3.medium", min_size = 2, max_size = 6 }
  }
  config = local.env_config[terraform.workspace]
}
```

Workspaces share the same code but have separate state files. Simpler structure, but riskier if you accidentally apply to the wrong workspace.

### Exercises

- Deploy the dev environment. Then deploy staging with a different VPC CIDR and instance type.
- Compare the state files — verify they're completely separate.
- If using directories: try changing a module and re-applying to just dev. Confirm staging is untouched.
- If using workspaces: practice `terraform workspace select` and `terraform workspace list`. Be very aware of which workspace you're in before running apply.

---

## Day 6–7: Clean Up & Reflect

### Tasks

1. **Review your module interfaces** — Are the variable names clear? Are there sensible defaults? Would someone else understand how to use these modules from the README alone?
2. **Add `description` to every variable and output.** This is a habit that pays off immediately when you or someone else reads the code later.
3. **Test destroy and re-apply** for each environment independently.
4. **Write a README** for the overall project explaining the module structure and how to deploy each environment.

### Bonus Challenges

- Add a `for_each` loop in the VPC module to create subnets dynamically based on `az_count`, rather than hardcoding two.
- Add `precondition` or `postcondition` blocks (Terraform 1.2+) inside your module resources for runtime validation.
- Study the source code of `terraform-aws-modules/vpc` on GitHub — compare their approach to yours.
- Create a `versions.tf` in each module with `required_providers` and `required_version` constraints.

---

## Key Concepts This Week

| Concept | Why It Matters |
|---|---|
| Module inputs (variables) | Define the module's API — what callers can customize |
| Module outputs | How modules share data with each other and the root module |
| Module composition | Wiring modules together through outputs → inputs |
| Directory-based environments | Safest way to isolate environments with separate state |
| Workspaces | Lighter-weight environment separation, same code |
| Variable validation | Catch misconfigurations before `apply` |
| `for_each` in modules | Dynamic resource creation based on input |
