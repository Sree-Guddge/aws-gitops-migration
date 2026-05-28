# infra/bootstrap/main.tf
# One-time provisioning of the Terraform state backend and GitHub OIDC provider.
#
# Apply order:
#   1. Run manually with a temporary bootstrap IAM role (TerraformBootstrapRole).
#   2. After apply, migrate the bootstrap state into itself (S3 backend).
#   3. All subsequent runs use the OIDC deploy roles.
#
# Import blocks handle the case where the S3 bucket and DynamoDB table were
# pre-created manually following scripts/bootstrap.md.

terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        ManagedBy = "terraform"
        Module    = "bootstrap"
      },
      var.tags
    )
  }
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# KMS key for state encryption
# ---------------------------------------------------------------------------

resource "aws_kms_key" "state" {
  description             = "KMS key for Terraform state bucket and DynamoDB lock table encryption"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true
  multi_region            = false

  policy = data.aws_iam_policy_document.state_key_policy.json

  tags = {
    Name = "terraform-state-bootstrap"
  }
}

resource "aws_kms_alias" "state" {
  name          = "alias/terraform-state-bootstrap"
  target_key_id = aws_kms_key.state.key_id
}

data "aws_iam_policy_document" "state_key_policy" {
  # Root account full access (required by AWS -- without this the key becomes unmanageable)
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

  # Bootstrap role can use the key during initial apply
  dynamic "statement" {
    for_each = var.bootstrap_role_arn != "" ? [var.bootstrap_role_arn] : []
    content {
      sid    = "AllowBootstrapRoleUsage"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = [statement.value]
      }
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey",
        "kms:CreateGrant",
      ]
      resources = ["*"]
    }
  }

  # Future GitHub Actions deploy roles can use the key for state operations
  dynamic "statement" {
    for_each = length(var.deploy_role_arns) > 0 ? [var.deploy_role_arns] : []
    content {
      sid    = "AllowDeployRoleUsage"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = statement.value
      }
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey",
      ]
      resources = ["*"]
    }
  }
}

# ---------------------------------------------------------------------------
# Access log bucket (must exist before the state bucket references it)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "logs" {
  bucket        = var.log_bucket_name
  force_destroy = false

  tags = {
    Name    = var.log_bucket_name
    Purpose = "terraform-state-access-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

# ---------------------------------------------------------------------------
# Terraform state bucket
# ---------------------------------------------------------------------------

# Import block: if the bucket was pre-created manually (scripts/bootstrap.md Step 2),
# this import brings it under Terraform management instead of failing with
# "BucketAlreadyOwnedByYou". Replace REPLACE_WITH_STATE_BUCKET_NAME with the
# actual bucket name before running terraform init/plan.
import {
  to = aws_s3_bucket.state
  id = var.state_bucket_name
}

resource "aws_s3_bucket" "state" {
  bucket        = var.state_bucket_name
  force_destroy = false

  tags = {
    Name    = var.state_bucket_name
    Purpose = "terraform-state"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "state" {
  bucket        = aws_s3_bucket.state.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "terraform-state-access-logs/"
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ---------------------------------------------------------------------------
# DynamoDB state lock table
# ---------------------------------------------------------------------------

# Import block: if the table was pre-created manually (scripts/bootstrap.md Step 3),
# this import brings it under Terraform management.
import {
  to = aws_dynamodb_table.lock
  id = var.dynamodb_table_name
}

resource "aws_dynamodb_table" "lock" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.state.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name    = var.dynamodb_table_name
    Purpose = "terraform-state-lock"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC provider
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.github_oidc_thumbprints

  tags = {
    Name    = "github-actions-oidc"
    Purpose = "github-oidc"
  }
}
