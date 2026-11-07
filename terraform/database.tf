# ---------------------------------------------------------------------------
# Databases: MySQL (business data) + PostgreSQL/pgvector (agent memory).
# Controls: private subnets only, encrypted with our KMS key, master password
# generated and stored by AWS Secrets Manager (never in Terraform/Git),
# automatic backups, deletion protection, Multi-AZ, IAM auth, log export.
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "data" {
  name       = "auto-monitor-${var.environment}-data"
  subnet_ids = aws_subnet.data[*].id
}

locals {
  databases = {
    mysql = {
      engine         = "mysql"
      engine_version = "8.4"
      db_name        = "monitor"
      log_exports    = ["audit", "error", "general", "slowquery"]
    }
    postgres = {
      engine         = "postgres"
      engine_version = "16"
      db_name        = "agent_memory"
      log_exports    = ["postgresql", "upgrade"]
    }
  }
}

# PostgreSQL: log every statement (query logging) for auditability.
resource "aws_db_parameter_group" "postgres" {
  name   = "auto-monitor-${var.environment}-pg16"
  family = "postgres16"

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1"
  }

  # Refuse unencrypted client connections (encryption in transit).
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}

resource "aws_db_parameter_group" "mysql" {
  name   = "auto-monitor-${var.environment}-mysql84"
  family = "mysql8.4"

  parameter {
    name  = "require_secure_transport"
    value = "1"
  }
}

data "aws_iam_policy_document" "rds_monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name               = "auto-monitor-${var.environment}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "db" {
  for_each = local.databases

  identifier     = "auto-monitor-${var.environment}-${each.key}"
  engine         = each.value.engine
  engine_version = each.value.engine_version
  instance_class = var.db_instance_class
  db_name        = each.value.db_name
  username       = "monitor_admin"

  # Password is generated + rotated by Secrets Manager, encrypted with our key.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.main.arn

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.main.arn

  db_subnet_group_name   = aws_db_subnet_group.data.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = true
  parameter_group_name   = each.key == "postgres" ? aws_db_parameter_group.postgres.name : aws_db_parameter_group.mysql.name

  iam_database_authentication_enabled = true
  auto_minor_version_upgrade          = true
  backup_retention_period             = 14
  copy_tags_to_snapshot               = true
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "auto-monitor-${var.environment}-${each.key}-final"

  enabled_cloudwatch_logs_exports       = each.value.log_exports
  monitoring_interval                   = 30
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.main.arn
  performance_insights_retention_period = 7
}
