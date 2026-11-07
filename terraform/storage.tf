# ---------------------------------------------------------------------------
# Storage: S3 buckets for (1) ALB access logs and (2) app backups.
# Controls: no public access, KMS/at-rest encryption, versioning,
# access logging, lifecycle (retention), TLS-only bucket policy.
# ---------------------------------------------------------------------------
#tfsec:ignore:aws-s3-enable-bucket-logging This IS the access-log bucket (EXC-04)
#trivy:ignore:AVD-AWS-0089 This IS the access-log bucket (EXC-04)
resource "aws_s3_bucket" "logs" {
  #checkov:skip=CKV_AWS_145:ALB access logs only support SSE-S3 (AES256), not KMS
  #checkov:skip=CKV_AWS_144:Single-region lab; cross-region replication = next iteration
  #checkov:skip=CKV2_AWS_62:No consumer for S3 event notifications in this iteration
  #checkov:skip=CKV_AWS_18:This IS the access-log bucket (logging it into itself would loop)
  bucket = "auto-monitor-${var.environment}-access-logs-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "backups" {
  #checkov:skip=CKV_AWS_144:Single-region lab; cross-region replication = next iteration
  #checkov:skip=CKV2_AWS_62:No consumer for S3 event notifications in this iteration
  bucket = "auto-monitor-${var.environment}-backups-${data.aws_caller_identity.current.account_id}"
}

# NOTE: these resources are written once per bucket on purpose (no for_each).
# tfsec/Trivy could not link "for_each over bucket objects" to the buckets and
# reported false positives; explicit resources keep all three scanners accurate.
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Backups use our KMS key. The ALB log bucket must use SSE-S3 (AES256):
# Elastic Load Balancing cannot write access logs into a KMS-encrypted bucket.
resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true
  }
}

#trivy:ignore:AVD-AWS-0132 ALB access logs only support SSE-S3 (approved exception EXC-03)
#tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Every access to the backups bucket is logged into the logs bucket.
resource "aws_s3_bucket_logging" "backups" {
  bucket        = aws_s3_bucket.backups.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3/backups/"
}

locals {
  # Shared lifecycle rule: cheaper storage after 30 days, purge old versions.
  bucket_ids = {
    logs    = aws_s3_bucket.logs.id
    backups = aws_s3_bucket.backups.id
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "all" {
  for_each = local.bucket_ids
  bucket   = each.value

  rule {
    id     = "retention"
    status = "Enabled"
    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Refuse any non-TLS request to the bucket.
data "aws_iam_policy_document" "backups" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.backups.arn, "${aws_s3_bucket.backups.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

data "aws_iam_policy_document" "logs" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Let the regional ELB log-delivery service write ALB access logs.
  statement {
    sid       = "AllowAlbAccessLogs"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/alb/*"]
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id
  policy = data.aws_iam_policy_document.backups.json
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs.json
}
