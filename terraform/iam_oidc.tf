# ---------------------------------------------------------------------------
# Pipeline identity: GitHub Actions -> AWS through OIDC federation.
#
# No permanent AWS access key exists anywhere. A GitHub job receives a signed
# OIDC token (valid minutes), AWS checks WHO is asking (repo + environment)
# and hands back short-lived credentials (1 hour max).
#
# Two roles = separation of duties:
#   * tf-plan  : READ-ONLY, any branch of the deployment repo may use it
#   * deployer : WRITE, ONLY jobs running in the protected "production"
#                GitHub environment (which requires human approval)
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  repo_subject = "repo:${var.github_owner}/${var.github_deploy_repo}"
}

# --- Read-only role used by validation / plan jobs --------------------------
data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.repo_subject}:*"]
    }
  }
}

resource "aws_iam_role" "tf_plan" {
  name                 = "auto-monitor-gha-tf-plan"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "tf_plan_readonly" {
  role       = aws_iam_role.tf_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# --- Deployer role: ONLY the protected production environment ---------------
data "aws_iam_policy_document" "deploy_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.repo_subject}:environment:production"]
    }
  }
}

resource "aws_iam_role" "deployer" {
  name                 = "auto-monitor-gha-deployer"
  assume_role_policy   = data.aws_iam_policy_document.deploy_trust.json
  max_session_duration = 3600
}

# The deployer can only send SSM commands to the app host (to pull the
# approved image digests and restart the stack) - it cannot create, delete
# or read anything else.
data "aws_iam_policy_document" "deployer" {
  statement {
    sid     = "RunDeployCommandOnAppHostOnly"
    actions = ["ssm:SendCommand"]
    resources = [
      aws_instance.app.arn,
      "arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript",
    ]
  }

  statement {
    sid = "ReadCommandResult"
    actions = [
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
    ]
    resources = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"]
  }
}

resource "aws_iam_role_policy" "deployer" {
  name   = "deploy-via-ssm-only"
  role   = aws_iam_role.deployer.id
  policy = data.aws_iam_policy_document.deployer.json
}
