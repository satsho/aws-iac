output "vpc_id" {
  description = "作成した VPC の ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC の CIDR"
  value       = aws_vpc.this.cidr_block
}

output "igw_id" {
  description = "Internet Gateway の ID"
  value       = aws_internet_gateway.this.id
}
