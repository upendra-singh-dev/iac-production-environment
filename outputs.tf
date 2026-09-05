output "url" { value = module.compute.url }
output "alb_dns_name" { value = module.compute.alb_dns_name }
output "assets_bucket" { value = aws_s3_bucket.assets.bucket }
output "db_secret_arn" { value = module.database.secret_arn }
output "egress_az" {
  description = "Single point of egress failure - see the runbook."
  value       = module.networking.egress_az
}
output "estimated_monthly_usd" {
  description = "Computed from this configuration, not from a price list read by hand."
  value       = local.cost_total
}
