# Terraform + AWS: Week 7 Study Guide

## Overview

This week you'll build a CI/CD pipeline for your Terraform code using GitHub Actions, add security scanning and linting, and implement a tagging and cost management strategy. This is where you shift from "Terraform that works" to "Terraform that's safe to run in a team."

---

## Day 1–2: GitHub Actions for Terraform

Set up a pipeline that runs `terraform plan` on pull requests and `terraform apply` on merge to main.

### OIDC Authentication (No Access Keys)

First, create the IAM infrastructure that lets GitHub Actions assume a role directly — no stored secrets needed.

```hcl
# oidc.tf
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# If the provider doesn't exist yet, create it:
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_actions" {
  name = "github-actions-terraform"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:YOUR_ORG/YOUR_REPO:*"
        }
      }
    }]
  })
}

# Attach the same permissions your Terraform needs
resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"  # Scope down later
}
```

### GitHub Actions Workflow

Create `.github/workflows/terraform.yml`:

```yaml
name: Terraform

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

permissions:
  id-token: write    # Required for OIDC
  contents: read
  pull-requests: write  # To comment plan output

env:
  AWS_REGION: ap-southeast-1
  TF_VERSION: "1.7.0"

jobs:
  plan:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::ACCOUNT_ID:role/github-actions-terraform
          aws-region: ${{ env.AWS_REGION }}

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init
        run: terraform init

      - name: Terraform Format Check
        run: terraform fmt -check -recursive

      - name: Terraform Validate
        run: terraform validate

      - name: Terraform Plan
        id: plan
        run: terraform plan -no-color -out=tfplan
        continue-on-error: true

      - name: Comment Plan on PR
        uses: actions/github-script@v7
        with:
          script: |
            const output = `#### Terraform Plan
            \`\`\`
            ${{ steps.plan.outputs.stdout }}
            \`\`\`
            `;
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: output
            });

      - name: Fail if plan failed
        if: steps.plan.outcome == 'failure'
        run: exit 1

  apply:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production  # Requires manual approval in GitHub settings
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::ACCOUNT_ID:role/github-actions-terraform
          aws-region: ${{ env.AWS_REGION }}

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init
        run: terraform init

      - name: Terraform Apply
        run: terraform apply -auto-approve
```

### Exercises

- Create a PR that changes a resource and observe the plan output as a PR comment.
- Merge the PR and watch the apply job run.
- Try submitting code with incorrect formatting — the `fmt -check` step should fail.
- Set up a GitHub Environment called "production" with a required reviewer for the apply job.

---

## Day 3: Linting & Security Scanning

Add automated checks to catch issues before they reach apply.

### tflint

Install and configure tflint to catch common mistakes:

Add to your GitHub Actions workflow:

```yaml
- name: Setup tflint
  uses: terraform-linters/setup-tflint@v4

- name: Run tflint
  run: |
    tflint --init
    tflint --recursive
```

Create a `.tflint.hcl` configuration file:

```hcl
plugin "aws" {
  enabled = true
  version = "0.30.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

rule "terraform_naming_convention" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}
```

### tfsec / Checkov

Add security scanning to catch misconfigurations:

```yaml
# Using checkov (Python-based, covers more than just Terraform)
- name: Run Checkov
  uses: bridgecrewio/checkov-action@v12
  with:
    directory: .
    quiet: true
    framework: terraform
    output_format: github_failed_only
```

Common issues Checkov catches:
- S3 buckets without encryption
- Security groups with 0.0.0.0/0 access
- RDS without encryption at rest
- Missing logging on ALBs
- IAM policies that are too permissive

### Exercises

- Run tflint locally on your Week 1–6 code and fix all warnings.
- Run Checkov locally (`pip install checkov && checkov -d .`) and review the findings.
- Some findings may be intentional (e.g., ALB on port 80 without HTTPS for learning). Use inline comments to skip those:

```hcl
#checkov:skip=CKV_AWS_91:ALB access logging not needed for learning environment
resource "aws_lb" "main" { ... }
```

---

## Day 4: Tagging Strategy & Default Tags

Implement a consistent tagging strategy across all resources.

### Provider Default Tags

```hcl
provider "aws" {
  region  = "ap-southeast-1"
  profile = "terraform"

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project
      ManagedBy   = "terraform"
      Owner       = var.owner
      CostCenter  = var.cost_center
    }
  }
}
```

### Tag Policy Validation

Create a `locals` block to enforce required tags:

```hcl
locals {
  required_tags = {
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terraform"
  }

  # Merge with any resource-specific tags
  common_tags = merge(local.required_tags, {
    Owner      = var.owner
    CostCenter = var.cost_center
  })
}
```

### Exercises

- Apply `default_tags` to your provider and run `terraform plan` on an existing project — notice tags being added to every resource.
- Try using `aws_organizations_policy` with a tag policy to enforce required tags at the AWS organization level.
- Use the AWS Cost Explorer to see costs grouped by your tags.

---

## Day 5: Cost Management with Infracost

Estimate the cost of your infrastructure before applying.

### Install and Configure

```bash
# Install infracost
brew install infracost  # or download from infracost.io

# Register for a free API key
infracost auth login
```

### Run Locally

```bash
# Generate a cost breakdown
infracost breakdown --path .

# Compare costs between two plans
infracost diff --path . --compare-to infracost-base.json
```

### Add to GitHub Actions

```yaml
- name: Setup Infracost
  uses: infracost/actions/setup@v3
  with:
    api-key: ${{ secrets.INFRACOST_API_KEY }}

- name: Generate Infracost diff
  run: |
    infracost diff \
      --path=. \
      --format=json \
      --out-file=/tmp/infracost.json

- name: Post Infracost comment
  uses: infracost/actions/comment@v1
  with:
    path: /tmp/infracost.json
    behavior: update
```

### Exercises

- Run `infracost breakdown` on each week's project and compare costs.
- Change an RDS instance from `db.t3.micro` to `db.t3.large` and use `infracost diff` to see the cost impact.
- Set up a cost budget:

```hcl
resource "aws_budgets_budget" "monthly" {
  name         = "${var.environment}-monthly-budget"
  budget_type  = "COST"
  limit_amount = "50"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
```

---

## Day 6–7: Clean Up & Reflect

### Tasks

1. **Verify your full pipeline** — Create a PR, review the plan + cost estimate + security scan, merge, and watch apply run.
2. **Document your CI/CD setup** — Include how OIDC works, what checks run, and how to add new environments.
3. **Review all security findings** from Checkov across your previous weeks' code. Fix what you can, document what you're intentionally skipping.

### Bonus Challenges

- Add Terraform plan output as a GitHub Actions artifact so you can download and inspect it.
- Create a separate workflow for `terraform destroy` that requires manual dispatch (`workflow_dispatch`).
- Add drift detection as a scheduled workflow (cron) that runs `terraform plan` nightly and alerts if changes are detected.
- Try `terraform test` (built-in from 1.6+) to write simple assertions about your configuration.

---

## Key Concepts This Week

| Concept | Why It Matters |
|---|---|
| OIDC federation | Eliminates stored AWS credentials in GitHub — gold standard for CI/CD |
| Plan on PR, apply on merge | Review infrastructure changes the same way you review code |
| tflint | Catches Terraform and AWS-specific mistakes before apply |
| Checkov / tfsec | Finds security misconfigurations automatically |
| Default tags | Consistent tagging without remembering to add tags to every resource |
| Infracost | Know the cost impact of changes before applying |
| GitHub Environments | Adds manual approval gates for production applies |
| Drift detection | Catches manual changes that bypass Terraform |
