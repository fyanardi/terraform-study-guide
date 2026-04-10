output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.vpc.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public_subnet[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private_subnet[*].id
}

output "web_security_group_id" {
  description = "Web Security Group ID"
  value       = aws_security_group.web_security_group.id
}

output "app_security_group_id" {
  description = "App Security Group ID"
  value       = aws_security_group.app_security_group.id
}
