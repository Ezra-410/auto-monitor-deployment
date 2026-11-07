# ---------------------------------------------------------------------------
# Compute: one EC2 host in a PRIVATE subnet runs the approved images with
# docker compose. No public IP, no SSH key, IMDSv2 only, encrypted disk.
# Administration happens through SSM Session Manager (audited, no open port).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app_host" {
  name               = "auto-monitor-${var.environment}-app-host"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# SSM agent permissions (managed policy, scoped by AWS to SSM actions only).
resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app_host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# The host may READ only the two DB secrets created by RDS - nothing else.
data "aws_iam_policy_document" "app_host" {
  statement {
    sid       = "ReadDbSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [for db in aws_db_instance.db : db.master_user_secret[0].secret_arn]
  }

  statement {
    sid       = "DecryptWithAppKey"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.main.arn]
  }

  statement {
    sid       = "WriteAppLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }
}

resource "aws_iam_role_policy" "app_host" {
  name   = "least-privilege"
  role   = aws_iam_role.app_host.id
  policy = data.aws_iam_policy_document.app_host.json
}

resource "aws_iam_instance_profile" "app_host" {
  name = "auto-monitor-${var.environment}-app-host"
  role = aws_iam_role.app_host.name
}

resource "aws_instance" "app" {
  ami                         = var.app_ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app_host.name
  associate_public_ip_address = false
  monitoring                  = true
  ebs_optimized               = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only (blocks SSRF credential theft)
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = 40
    volume_type           = "gp3"
    encrypted             = true
    kms_key_id            = aws_kms_key.main.arn
    delete_on_termination = true
  }

  tags = { Name = "auto-monitor-${var.environment}-app" }
}

# --- Public entry point: ALB (HTTPS only) protected by AWS WAF ---------------
# Approved exception EXC-01: the ALB is the only Internet-facing component.
#trivy:ignore:AVD-AWS-0053
#tfsec:ignore:aws-elb-alb-not-public
resource "aws_lb" "app" {
  name                       = "auto-monitor-${var.environment}"
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = aws_subnet.public[*].id
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true
  enable_deletion_protection = true

  access_logs {
    bucket  = aws_s3_bucket.logs.id
    prefix  = "alb"
    enabled = true
  }
}

resource "aws_lb_target_group" "frontend" {
  name     = "auto-monitor-frontend"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path    = "/api/_health"
    matcher = "200"
  }
}

resource "aws_lb_target_group_attachment" "frontend" {
  target_group_arn = aws_lb_target_group.frontend.arn
  target_id        = aws_instance.app.id
  port             = 3000
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_wafv2_web_acl" "app" {
  name  = "auto-monitor-${var.environment}"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "aws-common"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-common"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "aws-known-bad-inputs" # includes Log4j (Log4Shell) protection
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "aws-anonymous-ip" # blocks Tor exit nodes / anonymising proxies
    priority = 3
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAnonymousIpList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-anonymous-ip"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "auto-monitor-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "app" {
  resource_arn = aws_lb.app.arn
  web_acl_arn  = aws_wafv2_web_acl.app.arn
}

resource "aws_cloudwatch_log_group" "waf" {
  # WAF requires the log group name to start with "aws-waf-logs-"
  name              = "aws-waf-logs-auto-monitor-${var.environment}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn
}

resource "aws_wafv2_web_acl_logging_configuration" "app" {
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.app.arn
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/auto-monitor/${var.environment}/app"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn
}
