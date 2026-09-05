variable "name" { type = string }
variable "region" { type = string }
variable "account_id" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "private_subnet_ids" { type = list(string) }
variable "image" { type = string }
variable "container_port" { type = number }
variable "task_cpu" { type = number }
variable "task_memory" { type = number }
variable "desired_count" { type = number }
variable "ondemand_base" {
  type = number
  validation {
    condition     = var.ondemand_base >= 1
    error_message = "Keep one on-demand task: an all-Spot service can be reclaimed to zero."
  }
}
variable "certificate_arn" { type = string }
variable "domain_name" { type = string }
variable "db_secret_arn" { type = string }
variable "assets_bucket_arn" { type = string }
variable "assets_bucket_name" { type = string }
variable "ecr_repository_arn" { type = string }

locals {
  health_path        = "/healthz"
  log_retention_days = 14
  spot_weight        = 4
  ondemand_weight    = 1
}
