variable "region" {
    default = "ap-southeast-1"
}

variable "cidr_block" {
  description = "VPC CIDR block"
  default = "10.0.0.0/16"
}

variable "private_subnet" {
    type = list(string)
    default = ["10.0.1.0/24", "10.0.2.0/24"]
    description = "Private subnet"
}

variable "public_subnet" {
    type = list(string)
    default = ["10.0.3.0/24", "10.0.4.0/24"]
    description = "Public subnet"
}

variable "azs" {
    type = list(string)
    description = "Availability Zones"
    default = ["ap-southeast-1a", "ap-southeast-1b"]
}
