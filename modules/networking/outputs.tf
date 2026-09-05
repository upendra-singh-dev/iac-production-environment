output "vpc_id" { value = aws_vpc.this.id }
output "public_subnet_ids" { value = [for s in aws_subnet.public : s.id] }
output "private_subnet_ids" { value = [for s in aws_subnet.private : s.id] }
output "egress_az" {
  description = "AZ whose loss removes egress from every private subnet."
  value       = local.azs[0]
}
