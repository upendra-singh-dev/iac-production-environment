variable "name" { type = string }
variable "region" { type = string }
variable "vpc_cidr" { type = string }
variable "availability_zones" {
  type = list(string)
  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "An ALB requires subnets in at least two availability zones."
  }
}
