# modules/cloudtrail/main.tf
# Multi-region CloudTrail trail with S3 delivery and KMS encryption.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_cloudtrail" "this" {
  name                          = var.trail_name
  s3_bucket_name                = local.trail_bucket_id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = var.kms_key_arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Trail log bucket (prevent_destroy = true) - used for production environments
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "trail" {
  count = var.prevent_destroy ? 1 : 0

  bucket              = var.s3_bucket_name
  force_destroy       = false
  object_lock_enabled = true
  tags                = merge(var.tags, { Name = var.s3_bucket_name, Purpose = "cloudtrail", Region = data.aws_region.current.id })

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Trail log bucket (prevent_destroy = false) - used for ephemeral/test environments
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "trail_unprotected" {
  count = var.prevent_destroy ? 0 : 1

  bucket              = var.s3_bucket_name
  force_destroy       = false
  object_lock_enabled = true
  tags                = merge(var.tags, { Name = var.s3_bucket_name, Purpose = "cloudtrail", Region = data.aws_region.current.id })

  lifecycle {
    prevent_destroy = false
  }
}

locals {
  trail_bucket_id  = var.prevent_destroy ? aws_s3_bucket.trail[0].id : aws_s3_bucket.trail_unprotected[0].id
  trail_bucket_arn = var.prevent_destroy ? aws_s3_bucket.trail[0].arn : aws_s3_bucket.trail_unprotected[0].arn
}

resource "aws_s3_bucket_versioning" "trail" {
  bucket = local.trail_bucket_id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = local.trail_bucket_id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = local.trail_bucket_id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Object lock must be enabled on the bucket (object_lock_enabled = true above).
# COMPLIANCE mode with 7-year (2555 days) retention ensures tamper-proof audit logs.
resource "aws_s3_bucket_object_lock_configuration" "trail" {
  bucket = local.trail_bucket_id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 2555
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = local.trail_bucket_id
  policy = data.aws_iam_policy_document.trail_bucket.json
}

data "aws_iam_policy_document" "trail_bucket" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [local.trail_bucket_arn]
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${local.trail_bucket_arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}
