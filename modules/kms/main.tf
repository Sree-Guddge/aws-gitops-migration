# modules/kms/main.tf
# Creates a KMS key with a least-privilege key policy.
# Used for encrypting Terraform state, CloudTrail logs, and other sensitive data.

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# KMS key (prevent_destroy = true) - used for production/persistent environments
# ---------------------------------------------------------------------------
resource "aws_kms_key" "this" {
  count = var.prevent_destroy ? 1 : 0

  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true
  multi_region            = false

  policy = data.aws_iam_policy_document.key_policy.json

  tags = merge(var.tags, {
    Name   = var.alias
    Region = data.aws_region.current.id
  })

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# KMS key (prevent_destroy = false) - used for ephemeral/test environments
# ---------------------------------------------------------------------------
resource "aws_kms_key" "this_unprotected" {
  count = var.prevent_destroy ? 0 : 1

  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true
  multi_region            = false

  policy = data.aws_iam_policy_document.key_policy.json

  tags = merge(var.tags, {
    Name   = var.alias
    Region = data.aws_region.current.id
  })

  lifecycle {
    prevent_destroy = false
  }
}

locals {
  key_id  = var.prevent_destroy ? aws_kms_key.this[0].key_id : aws_kms_key.this_unprotected[0].key_id
  key_arn = var.prevent_destroy ? aws_kms_key.this[0].arn : aws_kms_key.this_unprotected[0].arn
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias}"
  target_key_id = local.key_id
}

data "aws_iam_policy_document" "key_policy" {
  # Root account can manage the key (required)
  statement {
    sid    = "EnableRootAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # CI/CD deploy roles can use the key
  statement {
    sid    = "AllowCIRoleUsage"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = var.ci_role_arns
    }
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }

  # Admin principals can manage (not use) the key
  statement {
    sid    = "AllowAdminManagement"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = var.admin_principal_arns
    }
    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
    ]
    resources = ["*"]
  }
}
