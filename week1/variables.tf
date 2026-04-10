variable "region" {
  default = "ap-southeast-1"
}

variable "environment" {
  type        = string
  description = "The deployment environment"
  default     = "dev"

  validation {
    # The condition must evaluate to true for the input to be valid
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "The environment must be one of: dev, staging, prod."
  }
}

variable "project" {
  type        = string
  description = "Name or ID of the deployment project"
  default     = "study-guide"
}

variable "cidr_block" {
  type        = string
  description = "VPC CIDR block"
  default     = "10.0.0.0/16"
}

variable "private_subnet_count" {
  type        = number
  default     = 2
  description = "Number of private subnets"
}

variable "public_subnet_count" {
  type        = number
  default     = 2
  description = "Number of public subnet"
}

variable "azs" {
  type        = list(string)
  description = "Availability Zones"
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
}

variable "allowed_ssh_cidr_blocks" {
  type        = list(string)
  description = "SSH CIDR blocks allowed to access the VPC"
}
