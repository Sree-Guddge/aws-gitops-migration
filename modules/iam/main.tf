# modules/iam/main.tf
# Creates the GitHub OIDC provider and per-environment deploy roles.
# No long-lived access keys are created.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# GitHub OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.github_oidc_thumbprints

  tags = var.tags
}

# Deploy role per environment
resource "aws_iam_role" "deploy" {
  for_each = var.deploy_roles

  name                 = each.value.role_name
  max_session_duration = 3600
  description          = "GitHub Actions OIDC deploy role for ${each.key} (${each.value.environment_name})"

  assume_role_policy = data.aws_iam_policy_document.github_trust[each.key].json

  tags = merge(var.tags, { Environment = each.value.environment_name })
}

data "aws_iam_policy_document" "github_trust" {
  for_each = var.deploy_roles

  statement {
    effect  = "Allow"
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

    # For prod: use StringEquals (not StringLike) to prevent bypass via branch name manipulation.
    # For dev/staging: StringLike is acceptable since subjects include wildcards (pull_request, refs/*).
    condition {
      test     = each.value.environment_name == "prod" ? "StringEquals" : "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value.allowed_subjects
    }

    # Prod-specific: additionally require the GitHub Actions environment claim to equal "production".
    # This ensures the role can only be assumed from a job running in the "production" GitHub environment,
    # providing an extra layer of protection beyond the sub claim.
    dynamic "condition" {
      for_each = each.value.environment_name == "prod" ? [1] : []
      content {
        test     = "StringEquals"
        variable = "token.actions.githubusercontent.com:environment"
        values   = ["production"]
      }
    }
  }
}

# Attach managed policies to deploy roles
resource "aws_iam_role_policy_attachment" "deploy" {
  for_each = {
    for item in flatten([
      for env, role in var.deploy_roles : [
        for policy_arn in role.policy_arns : {
          key        = "${env}-${policy_arn}"
          role_name  = aws_iam_role.deploy[env].name
          policy_arn = policy_arn
        }
      ]
    ]) : item.key => item
  }

  role       = each.value.role_name
  policy_arn = each.value.policy_arn
}

# Inline least-privilege policy for Terraform state access.
# No wildcard (*) actions -- all actions are explicitly enumerated.
resource "aws_iam_role_policy" "state_access" {
  for_each = var.deploy_roles

  name = "terraform-state-access"
  role = aws_iam_role.deploy[each.key].id

  policy = data.aws_iam_policy_document.state_access[each.key].json
}

data "aws_iam_policy_document" "state_access" {
  for_each = var.deploy_roles

  statement {
    sid    = "StateS3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      var.state_bucket_arn,
      "${var.state_bucket_arn}/${each.key}/*",
    ]
  }

  statement {
    sid    = "StateLockAccess"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]
    resources = [var.state_lock_table_arn]
  }

  statement {
    sid    = "StateKMSAccess"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [var.state_kms_key_arn]
  }
}
