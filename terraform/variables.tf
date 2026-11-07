variable "aws_region" {
  description = "AWS region hosting auto-monitor"
  type        = string
  default     = "eu-west-3"
}

variable "environment" {
  description = "Deployment environment name (staging | production)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

variable "owner" {
  description = "Team or person accountable for these resources"
  type        = string
  default     = "devsecops-team"
}

variable "availability_zones" {
  description = "Two availability zones used for HA (pinned, not discovered)"
  type        = list(string)
  default     = ["eu-west-3a", "eu-west-3b"]
}

variable "vpc_cidr" {
  description = "CIDR block of the auto-monitor VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "instance_type" {
  description = "EC2 instance type running the docker compose stack"
  type        = string
  default     = "t3.large"
}

variable "app_ami_id" {
  description = "Hardened AMI ID (Amazon Linux 2023 + Docker). Pin an ID, never 'latest'."
  type        = string
  default     = "ami-00000000000000000"
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for the HTTPS listener"
  type        = string
  default     = "arn:aws:acm:eu-west-3:111111111111:certificate/00000000-0000-0000-0000-000000000000"
}

variable "github_owner" {
  description = "GitHub user/org that owns the deployment repository (for OIDC trust)"
  type        = string
  default     = "Ezra-410"
}

variable "github_deploy_repo" {
  description = "Repository allowed to assume the deployment role through OIDC"
  type        = string
  default     = "auto-monitor-deployment"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "log_retention_days" {
  description = "CloudWatch log retention (>= 365 for audit evidence)"
  type        = number
  default     = 365
}
