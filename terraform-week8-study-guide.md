# Terraform + AWS: Week 8 Study Guide

## Overview

This final week focuses on operational skills: state management, importing existing resources, disaster recovery, and debugging. These are the skills that separate someone who can write Terraform from someone who can maintain it in production. Expect to spend a lot of time in the terminal and intentionally breaking things so you know how to fix them.

---

## Day 1–2: State Surgery

Learn to manipulate Terraform state when things go wrong.

### Common State Operations

```bash
# List all resources in state
terraform state list

# Show details of a specific resource
terraform state show aws_instance.web

# Move a resource (renamed it in code)
terraform state mv aws_instance.web aws_instance.app

# Remove a resource from state (Terraform forgets it, but it still exists in AWS)
terraform state rm aws_instance.legacy

# Pull the entire state file locally
terraform state pull > state_backup.json

# Push a state file (dangerous — use only for recovery)
terraform state push state_backup.json
```

### Renaming Resources with `moved` Blocks

Instead of `terraform state mv`, prefer `moved` blocks (Terraform 1.1+):

```hcl
moved {
  from = aws_instance.web
  to   = aws_instance.app
}
```

This is tracked in code, so the whole team sees the rename. After applying, you can remove the `moved` block.

### Refactoring into Modules

When you move a resource into a module, use `moved`:

```hcl
moved {
  from = aws_vpc.main
  to   = module.vpc.aws_vpc.main
}

moved {
  from = aws_subnet.public
  to   = module.vpc.aws_subnet.public
}
```

### Practice Scenarios

1. **Rename a resource** — Rename an `aws_security_group` in your code. Without `moved`, Terraform would destroy and recreate it. Add a `moved` block and verify the plan shows no changes.
2. **Remove from state** — Use `terraform state rm` on a non-critical resource (like an S3 object). Run `terraform plan` to see that Terraform now wants to create it again.
3. **Move between state files** — If you split a project into two, use `terraform state mv -state-out=other.tfstate` to migrate resources.

### Exercises

- Back up your state with `terraform state pull > backup.json` before every state operation.
- Practice `terraform state list | grep vpc` to find resources quickly.
- Intentionally corrupt state by editing the JSON (on a test project) and learn how to recover from the backup.

---

## Day 3: Importing Existing Resources

Bring existing AWS resources under Terraform management.

### Import with `import` Block (Terraform 1.5+)

The modern approach uses `import` blocks in your code:

```hcl
# Step 1: Write the resource configuration
resource "aws_s3_bucket" "existing" {
  bucket = "my-existing-bucket-name"
}

# Step 2: Add the import block
import {
  to = aws_s3_bucket.existing
  id = "my-existing-bucket-name"
}
```

Run `terraform plan` to preview, then `terraform apply` to import. After a successful import, remove the `import` block.

### Generate Configuration Automatically

```bash
# Terraform 1.5+ can generate the HCL for you
terraform plan -generate-config-out=generated.tf
```

This creates a `generated.tf` file with the full resource configuration based on the real resource. Review and clean up the generated code before committing.

### CLI Import (Legacy)

```bash
# Write the resource block first, then:
terraform import aws_s3_bucket.existing my-existing-bucket-name
```

### Import Exercise

1. Create a security group manually in the AWS Console.
2. Write a matching `aws_security_group` resource in Terraform.
3. Import it using the `import` block approach.
4. Run `terraform plan` — you'll likely see some differences. Adjust your configuration until the plan shows no changes.

### Common Import IDs

| Resource | Import ID Format |
|---|---|
| `aws_instance` | Instance ID (`i-1234567890abcdef0`) |
| `aws_s3_bucket` | Bucket name |
| `aws_security_group` | Security group ID (`sg-12345`) |
| `aws_vpc` | VPC ID (`vpc-12345`) |
| `aws_db_instance` | DB identifier |
| `aws_iam_role` | Role name |
| `aws_lambda_function` | Function name |
| `aws_route53_record` | `zone_id_record-name_record-type` |

### Exercises

- Import at least three different resource types manually created in the console.
- Use `terraform plan -generate-config-out=generated.tf` and compare the generated code with what you would have written manually.
- Try importing a resource with the wrong configuration — observe the diff and fix it.

---

## Day 4: Debugging & Troubleshooting

Build your debugging toolkit for when things go wrong.

### Enable Debug Logging

```bash
# Set log level (TRACE is most verbose)
export TF_LOG=DEBUG
terraform plan

# Save logs to a file
export TF_LOG_PATH=terraform.log
terraform plan

# Disable when done
unset TF_LOG
unset TF_LOG_PATH
```

### Common Issues & Fixes

**1. Dependency Cycles**

```
Error: Cycle: aws_security_group.a, aws_security_group.b
```

Fix: Use `aws_security_group_rule` as separate resources instead of inline `ingress`/`egress` blocks.

**2. Resource Already Exists**

```
Error: creating S3 Bucket: BucketAlreadyExists
```

Fix: Import the existing resource into state, or choose a different name.

**3. Timeout Errors**

```
Error: waiting for RDS DB Instance: timeout while waiting for state to become 'available'
```

Fix: Add custom timeouts:

```hcl
resource "aws_db_instance" "main" {
  # ...
  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}
```

**4. Provider Authentication Errors**

```
Error: No valid credential sources found
```

Fix: Verify `aws configure list --profile terraform` shows valid credentials. Check if credentials have expired (especially SSO sessions).

**5. State Lock Errors**

```
Error: Error acquiring the state lock
```

Fix: If the lock is stale (crashed apply), force-unlock:

```bash
terraform force-unlock LOCK_ID
```

### Exercises

- Enable `TF_LOG=DEBUG` and run a plan. Read through the output to understand the provider API calls.
- Create a dependency cycle intentionally (two security groups referencing each other with inline rules). Fix it using separate `aws_security_group_rule` resources.
- Force a state lock (open two terminals, run apply in both). Practice force-unlocking.

---

## Day 5: Disaster Recovery & State Recovery

Practice recovering from the worst-case scenarios.

### Scenario 1: State File Deleted

1. Delete your local state (or the remote state file from S3).
2. Recover from the S3 bucket versioning — download the previous version.
3. Use `terraform state push` to restore.

### Scenario 2: State Mismatch

1. Manually modify a resource in the AWS Console (e.g., change a security group rule).
2. Run `terraform plan` — observe the drift.
3. Decide: apply Terraform's config to overwrite the manual change, or update your Terraform code to match reality.

### Scenario 3: Partial Apply Failure

1. Create a configuration with a resource that will fail mid-apply (e.g., an invalid AMI ID after a valid S3 bucket).
2. Observe how Terraform's state reflects the partial success.
3. Fix the error and re-apply — Terraform picks up where it left off.

### Scenario 4: Recovering from `terraform state rm`

1. Remove a resource from state with `terraform state rm`.
2. The resource still exists in AWS but Terraform thinks it doesn't.
3. Re-import the resource using `import` blocks.

### Exercises

- Practice each disaster scenario on a test project (not your main infrastructure).
- Create a "break glass" runbook document for your team listing steps for each recovery scenario.
- Verify your S3 state bucket versioning is working — list previous versions in the console.

---

## Day 6–7: Capstone & Reflect

### Capstone Project

Build a complete environment from scratch that combines everything you've learned:

```
capstone/
├── modules/
│   ├── vpc/
│   ├── ecs/
│   ├── rds/
│   └── serverless/
├── environments/
│   ├── dev/
│   └── prod/
├── .github/
│   └── workflows/
│       └── terraform.yml
├── .tflint.hcl
└── README.md
```

Requirements:
- VPC with public and private subnets (module)
- ECS Fargate service or Auto Scaling Group for the web tier
- RDS PostgreSQL in private subnets
- At least one Lambda function (e.g., a cron job or API endpoint)
- Remote state with locking
- CI/CD pipeline with plan, scan, and apply
- Default tags on all resources
- Proper security groups (least privilege)
- Outputs for all key endpoints
- Comprehensive README

### Final Review Checklist

- [ ] Can you `terraform destroy` and `terraform apply` the entire stack from zero?
- [ ] Are all secrets managed through Secrets Manager (not plain text)?
- [ ] Is state encrypted and access-controlled?
- [ ] Do all resources have consistent tags?
- [ ] Does Checkov / tfsec pass (or have documented exceptions)?
- [ ] Can you import an existing resource into your state?
- [ ] Can you rename a resource without destroying it?
- [ ] Do you know how to recover from a corrupted or deleted state file?
- [ ] Is your CI/CD pipeline using OIDC (no stored credentials)?
- [ ] Can a new team member read your README and understand the architecture?

### Writing Your Study Notes

Document what you'd tell your past self about Terraform:
- What were the biggest surprises?
- Which mistakes cost you the most time?
- What patterns will you reuse in every project?
- What would you do differently next time?

---

## Where to Go Next

After completing this 8-week guide, consider exploring:

- **Terraform Cloud / HFC** — managed state, runs, and policy enforcement
- **Terragrunt** — a wrapper that reduces boilerplate for multi-environment setups
- **EKS with Terraform** — Kubernetes cluster provisioning and add-on management
- **Multi-account strategy** — AWS Organizations, Control Tower, and cross-account roles
- **Custom providers** — writing your own Terraform provider for internal services
- **Policy as code** — OPA (Open Policy Agent) or Sentinel for enforcing organizational rules
- **CDK for Terraform (CDKTF)** — write Terraform in Python, TypeScript, or Go

---

## Key Concepts This Week

| Concept | Why It Matters |
|---|---|
| `terraform state mv` | Rename or refactor without destroying resources |
| `moved` blocks | Track refactoring in version control |
| `import` blocks | Bring existing AWS resources under Terraform management |
| `-generate-config-out` | Auto-generate HCL for imported resources |
| `TF_LOG=DEBUG` | Essential for diagnosing provider and API issues |
| `force-unlock` | Recovery from stale state locks |
| State file versioning | Your safety net for state corruption or deletion |
| Drift detection | Catches manual changes that bypass Terraform |
