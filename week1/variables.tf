variable "region" {
    default = "ap-southeast-1"
}

variable "cidr_block" {
  description = "VPC CIDR block"
  default = "10.0.0.0/16"
}

variable "private_subnet_count" {
    type = number
    default = 2
    description = "Number of private subnets"
}

variable "public_subnet_count" {
    type = number
    default = 2
    description = "Number of public subnet"
}

variable "azs" {
    type = list(string)
    description = "Availability Zones"
    default = ["ap-southeast-1a", "ap-southeast-1b"]
}
