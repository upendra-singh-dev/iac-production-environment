variable "name" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "app_security_group_id" { type = string }
variable "db_name" { type = string }
variable "master_username" { type = string }
variable "engine_version" { type = string }
variable "instance_class" { type = string }
variable "allocated_storage" { type = number }
variable "multi_az" { type = bool }
variable "backup_retention_days" {
  type = number
  validation {
    condition     = var.backup_retention_days >= 1
    error_message = "Single-AZ with no automated backup has no recovery path; retention must be >= 1."
  }
}
