# Terraform + AWS: 8-Week Study Guide Overview

A practical study guide to level up your Terraform skills with AWS, organised into four phases covering core infrastructure through to production operations.

---

## Phase 1: Core Infrastructure Patterns (Week 1–2)

Start by building these common real-world setups from scratch, each as its own project:

1. **VPC with public/private subnets** — Create a multi-AZ VPC with NAT gateways, route tables, and security groups. This is the foundation of almost every AWS deployment.
2. **EC2 + ALB + Auto Scaling Group** — Deploy a web app behind a load balancer with scaling policies based on CPU. Practice with `user_data` scripts for bootstrapping.
3. **S3 + CloudFront static site** — Set up a static website with a CDN, custom domain via Route 53, and ACM certificate.

---

## Phase 2: State & Modules (Week 3–4)

4. **Remote state with S3 + DynamoDB** — Move your state to S3 with locking. Break things intentionally (e.g., corrupt state, import existing resources with `terraform import`) to learn recovery.
5. **Write reusable modules** — Refactor your VPC and EC2 projects into modules with variables, outputs, and validation. Publish one to a private registry or just reference it locally.
6. **Multi-environment setup** — Use workspaces or directory-based separation (`envs/dev`, `envs/prod`) to manage dev/staging/prod with the same modules but different `tfvars`.

---

## Phase 3: Real-World Services (Week 5–6)

7. **RDS + Secrets Manager** — Provision a PostgreSQL RDS instance with automated backups, and store credentials in Secrets Manager. Practice `lifecycle` blocks (e.g., `prevent_destroy`).
8. **ECS Fargate service** — Deploy a containerized app on Fargate with an ALB, CloudWatch logging, and IAM task roles. This is a very common production pattern.
9. **Lambda + API Gateway** — Build a serverless API. Package and deploy Lambda code with Terraform, wire up API Gateway, and manage permissions.

---

## Phase 4: Operations & CI/CD (Week 7–8)

10. **CI/CD pipeline for Terraform** — Set up GitHub Actions (or CodePipeline) to run `terraform plan` on PRs and `terraform apply` on merge. Add `tflint` and `checkov`/`tfsec` for policy checks.
11. **Tagging strategy & cost controls** — Implement `default_tags` in the provider block, use `aws_budgets_budget`, and explore `infracost` to estimate costs from your plans.
12. **Drift detection & disaster recovery** — Schedule `terraform plan` runs to detect drift. Practice `terraform state mv`, `terraform state rm`, and full state recovery.

---

## Ongoing Exercises

- **Destroy and rebuild** — Regularly `terraform destroy` and re-apply to prove your code is truly reproducible.
- **Read real modules** — Study the source code of popular modules on the Terraform Registry (e.g., `terraform-aws-modules/vpc`, `terraform-aws-modules/eks`).
- **Add one new resource a day** — Pick an AWS service you haven't used (SQS, SNS, EventBridge, Step Functions) and write the Terraform for it.

---

## Key Resources

- `registry.terraform.io` — Official provider docs and community modules
- "Terraform: Up & Running" by Yevgeniy Brikman — The best intermediate-to-advanced book
- `github.com/terraform-aws-modules` — Battle-tested module examples
- HashiCorp Learn tutorials on state management and modules

---

## Weekly Guide Files

| Week | Focus Area | File |
|------|-----------|------|
| 1 | VPC, EC2, ALB, Auto Scaling | `terraform-week1-study-guide.md` |
| 2 | S3 Static Site, CloudFront, Remote State | `terraform-week2-study-guide.md` |
| 3 | Modules, Multi-Environment Setup | `terraform-week3-study-guide.md` |
| 4 | RDS, Secrets Manager, Lifecycle Rules, Data Sources | `terraform-week4-study-guide.md` |
| 5 | ECS Fargate, ECR, ECS Auto Scaling | `terraform-week5-study-guide.md` |
| 6 | Lambda, API Gateway, DynamoDB, Lambda Layers | `terraform-week6-study-guide.md` |
| 7 | GitHub Actions CI/CD, Linting, Security Scanning, Cost Management | `terraform-week7-study-guide.md` |
| 8 | State Surgery, Importing, Debugging, Disaster Recovery, Capstone | `terraform-week8-study-guide.md` |

---

The single best habit: after each project, write a short README explaining what you built and what tripped you up. It solidifies learning faster than anything else.
