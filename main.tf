provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Environment = var.name
      ManagedBy   = "terraform"
      Repository  = "iac-production-environment"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" { state = "available" }

locals {
  # On-demand rates, kept beside the resources they price so changing an
  # instance class moves the estimate in the same commit.
  price = {
    fargate_vcpu_hour  = 0.04048
    fargate_gb_hour    = 0.004445
    spot_discount      = 0.70
    rds_t4g_micro_hour = 0.016
    gp3_gb_month       = 0.115
    alb_hour           = 0.0225
    alb_lcu_month      = 5.84
    nat_hour           = 0.045
    secret_month       = 0.40
    logs_gb_month      = 0.50
    egress_estimate    = 12.00 # ~100GB out plus NAT processing
  }
  hours = 730

  db_instances  = var.db_multi_az ? 2 : 1
  task_cpu      = 256
  task_memory   = 512
  desired_count = 2
  spot_tasks    = local.desired_count - 1 # one on-demand task is the floor

  cost = {
    fargate = (
      (local.spot_tasks * (1 - local.price.spot_discount) + 1) *
      ((local.task_cpu / 1024) * local.price.fargate_vcpu_hour +
      (local.task_memory / 1024) * local.price.fargate_gb_hour) * local.hours
    )
    rds  = local.db_instances * local.price.rds_t4g_micro_hour * local.hours
    disk = local.db_instances * 20 * local.price.gp3_gb_month
    alb  = local.price.alb_hour * local.hours + local.price.alb_lcu_month
    nat  = local.price.nat_hour * local.hours
    # Variable spend that grows with traffic: egress, NAT per-GB, ECR storage.
    misc = local.price.secret_month + 5 * local.price.logs_gb_month + local.price.egress_estimate
  }
}

locals {
  cost_total = local.cost.fargate + local.cost.rds + local.cost.disk + local.cost.alb + local.cost.nat + local.cost.misc
}

# The cap is enforced, not asserted: raise an instance class and the plan fails.
check "within_budget" {
  assert {
    condition     = local.cost_total <= var.monthly_budget_usd
    error_message = "Estimated ${format("$%.2f", local.cost_total)}/mo exceeds the ${format("$%.0f", var.monthly_budget_usd)} cap."
  }
}

module "networking" {
  source             = "./modules/networking"
  name               = var.name
  region             = var.region
  vpc_cidr           = var.vpc_cidr
  availability_zones = data.aws_availability_zones.available.names
}

module "database" {
  source                = "./modules/database"
  name                  = var.name
  vpc_id                = module.networking.vpc_id
  private_subnet_ids    = module.networking.private_subnet_ids
  app_security_group_id = module.compute.task_security_group_id
  db_name               = "northwind"
  master_username       = "app"
  engine_version        = "16.4"
  instance_class        = "db.t4g.micro"
  allocated_storage     = 20
  multi_az              = var.db_multi_az
  backup_retention_days = 7 # PITR window; the recovery story for single-AZ
}

module "compute" {
  source             = "./modules/compute"
  name               = var.name
  region             = var.region
  account_id         = data.aws_caller_identity.current.account_id
  vpc_id             = module.networking.vpc_id
  public_subnet_ids  = module.networking.public_subnet_ids
  private_subnet_ids = module.networking.private_subnet_ids
  image              = var.image
  container_port     = 8080
  task_cpu           = local.task_cpu
  task_memory        = local.task_memory
  desired_count      = local.desired_count
  ondemand_base      = 1
  certificate_arn    = var.certificate_arn
  domain_name        = var.domain_name
  db_secret_arn      = module.database.secret_arn
  assets_bucket_arn  = aws_s3_bucket.assets.arn
  assets_bucket_name = aws_s3_bucket.assets.bucket
  ecr_repository_arn = var.ecr_repository_arn
}

resource "aws_s3_bucket" "assets" {
  bucket = "${var.name}-assets-${data.aws_caller_identity.current.account_id}"
}

# No SSE block: S3 applies SSE-S3 to every new bucket by default.
resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

