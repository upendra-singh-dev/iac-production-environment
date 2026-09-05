terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.70" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }

  # Partial config: bucket comes from -backend-config, so one repo serves any
  # account. Runbook covers the one-off bootstrap.

  backend "s3" {
    key            = "production/terraform.tfstate"
    encrypt        = true
    dynamodb_table = "tf-state-lock"
  }

}
