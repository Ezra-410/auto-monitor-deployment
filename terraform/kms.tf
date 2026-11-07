# ---------------------------------------------------------------------------
# KMS: one customer-managed key encrypts storage, databases, logs and secrets.
# Rotation is ON (yearly) and the key policy is explicit (no implicit trust).
# ---------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kms" {
  # Approved exceptions (KMS key policies always use "*" = "this key"):
  #checkov:skip=CKV_AWS_111:Key policy - resource "*" refers only to this key
  #checkov:skip=CKV_AWS_356:Key policy - resource "*" refers only to this key
  #checkov:skip=CKV_AWS_109:Key policy - account root must administer the key (break-glass)
  # Account root keeps administrative control of the key (break-glass).
  statement {
    sid       = "AccountAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"] # In a key policy, "*" means "this key" only.

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # CloudWatch Logs must be allowed to use the key to encrypt log groups.
  statement {
    sid       = "AllowCloudWatchLogs"
    effect    = "Allow"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "main" {
  description             = "auto-monitor ${var.environment} encryption key"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "main" {
  name          = "alias/auto-monitor-${var.environment}"
  target_key_id = aws_kms_key.main.key_id
}
