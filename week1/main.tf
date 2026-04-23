terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.40.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = "terraform"

  default_tags {
    tags = {
      Environment = var.environment
    }
  }
}

locals {
  prefix = "${var.project}-${var.environment}"
}
