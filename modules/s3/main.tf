# modules/s3/main.tf
# Reusable S3 bucket module that enforces the security baseline on every bucket it creates.
# Security baseline includes: public access block, KMS encryption, versioning,
# lifecycle rules, and optional access logging.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Bucket (prevent_destroy = true) - used for all production/persistent buckets
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "this" {
  count = var.prevent_destroy ? 1 : 0

  bucket        = var.bucket_name
  force_destroy = false

  tags = merge(var.tags, {
    Name = var.bucket_name
  })

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Bucket (prevent_destroy = false) - used for ephemeral/test buckets only
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "this_unprotected" {
  count = var.prevent_destroy ? 0 : 1

  bucket        = var.bucket_name
  force_destroy = false

  tags = merge(var.tags, {
    Name = var.bucket_name
  })

  lifecycle {
    prevent_destroy = false
  }
}

# ---------------------------------------------------------------------------
# Local reference to whichever bucket resource was created
# ---------------------------------------------------------------------------
locals {
  bucket_id  = var.prevent_destroy ? aws_s3_bucket.this[0].id : aws_s3_bucket.this_unprotected[0].id
  bucket_arn = var.prevent_destroy ? aws_s3_bucket.this[0].arn : aws_s3_bucket.this_unprotected[0].arn
}

# ---------------------------------------------------------------------------
# Public access block - all four settings enforced
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = local.bucket_id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# Server-side encryption with KMS
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = local.bucket_id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# ---------------------------------------------------------------------------
# Versioning
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "this" {
  bucket = local.bucket_id

  versioning_configuration {
    status = "Enabled"
  }
}

# ---------------------------------------------------------------------------
# Lifecycle configuration
#   - Expire noncurrent versions after 90 days
#   - Abort incomplete multipart uploads after 7 days
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = local.bucket_id

  # Versioning must be enabled before lifecycle rules referencing noncurrent
  # versions can be applied.
  depends_on = [aws_s3_bucket_versioning.this]

  rule {
    id     = "noncurrent-version-expiration"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ---------------------------------------------------------------------------
# Access logging (optional - enabled when var.log_bucket_name is non-empty)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_logging" "this" {
  count = var.log_bucket_name != "" ? 1 : 0

  bucket        = local.bucket_id
  target_bucket = var.log_bucket_name
  target_prefix = "${var.bucket_name}/"
}
