# ---------------------------------------------------------------------------
# Terraform & provider versions are PINNED so every run uses the same code.
# (Supply-chain control: an unpinned provider could change behaviour silently.)
# ---------------------------------------------------------------------------
terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }

  # Remote state: encrypted S3 bucket + state locking.
  # Kept commented because this lab has no AWS account. In a real setup the
  # state file contains sensitive data (DB endpoints, ARNs), so it must never
  # be committed to Git and must be stored encrypted with restricted access.
  # backend "s3" {
  #   bucket       = "auto-monitor-tfstate-<account-id>"
  #   key          = "prod/terraform.tfstate"
  #   region       = "eu-west-3"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "auto-monitor"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }
}
