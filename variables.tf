variable "name" {
  type        = string
  description = "Environment name; prefixes every resource."
  default     = "northwind-prod"
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "image" {
  type        = string
  description = "Fully qualified ECR image URI, including tag or digest."
}

variable "ecr_repository_arn" {
  type        = string
  description = "Repository the execution role may pull from - and only that one."
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate in this region for domain_name."
}

variable "domain_name" {
  type        = string
  description = "Public hostname; point it at the ALB once apply completes."
}

variable "monthly_budget_usd" {
  type    = number
  default = 150

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "A budget of zero cannot provision anything."
  }
}

variable "db_multi_az" {
  type        = bool
  default     = false
  description = <<-EOT
    Single-AZ is the shipped trade-off. Multi-AZ also fits the cap on this
    instance class ($99.71 of $150) but buys a standby of the same undersized
    class and addresses only one of three identified single points of failure.
    Flip it and the cost model re-checks the cap automatically.
  EOT
}
