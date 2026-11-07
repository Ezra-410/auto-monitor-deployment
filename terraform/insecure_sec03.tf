# ===========================================================================
# SEC-03 - DELIBERATELY INSECURE TERRAFORM (test branch only, never merge!)
# Copy this file into terraform/ on branch test/sec-03-insecure-iac.
# Every block below is a classic real-world cloud breach pattern.
# ===========================================================================

# 1) Database open to the whole Internet, unencrypted, no backups
resource "aws_security_group" "sec03_db_open" {
  name        = "sec03-db-open"
  description = "BAD: MySQL open to the world"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "MySQL from anywhere"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "sec03_public_db" {
  identifier              = "sec03-public-db"
  engine                  = "mysql"
  engine_version          = "8.4"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  username                = "admin"
  password                = "Password123!" # hardcoded credential
  publicly_accessible     = true
  storage_encrypted       = false
  backup_retention_period = 0
  skip_final_snapshot     = true
  vpc_security_group_ids  = [aws_security_group.sec03_db_open.id]
}

# 2) Storage bucket without encryption, versioning or public access block
resource "aws_s3_bucket" "sec03_unencrypted" {
  bucket = "sec03-unencrypted-notes-export"
}

resource "aws_s3_bucket_acl" "sec03_public_read" {
  bucket = aws_s3_bucket.sec03_unencrypted.id
  acl    = "public-read"
}

# 3) Excessive IAM permissions: full admin "*:*"
resource "aws_iam_policy" "sec03_admin" {
  name   = "sec03-god-mode"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "*"
      Resource = "*"
    }]
  })
}
