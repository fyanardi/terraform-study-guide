# Terraform + AWS: Week 2 Study Guide

## Overview

This week focuses on two common AWS patterns: hosting a static website with S3 and CloudFront, and setting up remote state management. These are foundational skills — nearly every production Terraform project uses remote state, and static hosting is one of the most cost-effective ways to serve web content.

---

## Day 1–2: S3 Static Website

Build a fully functional static website hosted on S3.

### Resources to Build

1. **`aws_s3_bucket`** — Create a bucket for your website files.
2. **`aws_s3_bucket_website_configuration`** — Enable static website hosting, set `index.html` as the index document and `error.html` as the error document.
3. **`aws_s3_bucket_public_access_block`** — Understand the default "block all public access" settings. You'll need to allow public access for a plain S3 website (CloudFront will change this later).
4. **`aws_s3_bucket_policy`** — Attach a policy that allows `s3:GetObject` for everyone.
5. **`aws_s3_object`** — Upload a simple `index.html` and `error.html` using Terraform's `file()` function or `content` attribute.

### Exercises

- Visit the S3 website endpoint in your browser and confirm the page loads.
- Try uploading a file with the wrong `content_type` and observe what happens (e.g., HTML rendered as plain text).
- Delete the bucket policy and observe the 403 error. Re-apply to fix it.

---

## Day 3–4: CloudFront + ACM + Route 53

Put a CDN in front of your S3 site with HTTPS and a custom domain.

### Resources to Build

1. **`aws_cloudfront_distribution`** — Origin set to your S3 bucket. Configure default cache behavior, set `viewer_protocol_policy` to `redirect-to-https`.
2. **`aws_cloudfront_origin_access_control`** — Use OAC (not the older OAI) so CloudFront can access S3 privately. Update the S3 bucket policy to allow only CloudFront, and remove public access.
3. **`aws_acm_certificate`** — Request a certificate for your domain. **Important:** ACM certificates for CloudFront must be in `us-east-1`. Use an aliased provider:

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  profile = "terraform"
}

resource "aws_acm_certificate" "cert" {
  provider          = aws.us_east_1
  domain_name       = "example.com"
  validation_method = "DNS"
}
```

4. **`aws_acm_certificate_validation`** — Automate DNS validation using Route 53 records.
5. **`aws_route53_zone`** — Reference your hosted zone (or create one if you own a domain).
6. **`aws_route53_record`** — Create an A record (alias) pointing to the CloudFront distribution.

### Exercises

- Access your site via the CloudFront URL and confirm HTTPS works.
- Invalidate the CloudFront cache manually in the console after changing `index.html`. Understand why CDN caching matters.
- Try adding a second domain (e.g., `www.example.com`) as a CloudFront alias with a corresponding Route 53 record.
- If you don't own a domain, skip Route 53/ACM and just use the CloudFront distribution URL — the core concepts still apply.

---

## Day 5: Remote State Setup

Move your state from local to S3 with locking — this is a critical production practice.

### Resources to Build (Bootstrap Project)

Create a small, separate Terraform project just for the state infrastructure:

1. **`aws_s3_bucket`** — For storing state files. Enable versioning so you can recover previous states.
2. **`aws_s3_bucket_versioning`** — Turn on versioning.
3. **`aws_s3_bucket_server_side_encryption_configuration`** — Enable AES256 or KMS encryption.
4. **`aws_s3_bucket_public_access_block`** — Block all public access.
5. **`aws_dynamodb_table`** — For state locking. Must have a partition key named `LockID` of type String.

### Configure Backend in Your Main Project

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket"
    key            = "week2/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
    profile        = "terraform"
  }
}
```

Run `terraform init` and Terraform will offer to migrate your local state to S3.

### Exercises

- Open the S3 bucket in the console and inspect the state file. Understand that it contains sensitive data (resource IDs, sometimes passwords).
- Open two terminals and run `terraform apply` simultaneously — observe the lock in action.
- Check the DynamoDB table during an apply to see the lock entry.
- Try `terraform state pull` to download the remote state locally, and `terraform state push` to understand how manual recovery works (be careful with this one).

---

## Day 6–7: Clean Up & Reflect

### Tasks

1. **Organize your projects** — You should now have two projects: the state bootstrap project and your main infrastructure project. Keep them in separate directories.
2. **Run `terraform destroy`** on your main project (CloudFront + S3 site), then re-apply from zero.
3. **Document your learnings** — Write a README covering multi-region providers, CloudFront caching behavior, and remote state.

### Bonus Challenges

- Add a `lifecycle` rule to the S3 state bucket to expire old versions after 90 days.
- Create a `null_resource` with a `local-exec` provisioner that runs `aws cloudfront create-invalidation` after updating S3 objects — this automates cache invalidation.
- Try breaking the state intentionally: delete a resource from the console, then run `terraform plan` to see how Terraform reacts. Use `terraform state rm` to fix the mismatch.

---

## Suggested File Structure (End of Week)

```
week2-state-bootstrap/
├── main.tf
├── variables.tf
├── outputs.tf
└── README.md

week2-static-site/
├── main.tf            # Provider config (including us-east-1 alias)
├── variables.tf
├── terraform.tfvars
├── outputs.tf
├── s3.tf              # Bucket, website config, policy
├── cloudfront.tf      # Distribution, OAC
├── dns.tf             # Route 53 records, ACM certificate
├── .gitignore
└── README.md
```

---

## Key Concepts This Week

| Concept | Why It Matters |
|---|---|
| S3 website hosting | Cheapest way to serve static content on AWS |
| CloudFront OAC | Keeps your S3 bucket private while serving via CDN |
| Multi-region providers | Some AWS services (like ACM for CloudFront) require specific regions |
| Remote state in S3 | Enables team collaboration and prevents local state loss |
| DynamoDB state locking | Prevents concurrent applies from corrupting state |
| State file security | State contains secrets — encrypt and restrict access |
