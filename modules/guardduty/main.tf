# modules/guardduty/main.tf
# Enables GuardDuty with S3 protection and findings export to a managed S3 bucket.

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# GuardDuty detector
# ---------------------------------------------------------------------------

resource "aws_guardduty_detector" "this" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Findings S3 bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "findings" {
  bucket = var.findings_bucket_name

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "findings" {
  bucket = aws_s3_bucket.findings.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "findings" {
  bucket = aws_s3_bucket.findings.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "findings" {
  bucket = aws_s3_bucket.findings.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# ---------------------------------------------------------------------------
# Bucket policy - grants GuardDuty service principal write access
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "findings" {
  bucket = aws_s3_bucket.findings.id
  policy = data.aws_iam_policy_document.findings_bucket_policy.json

  depends_on = [aws_s3_bucket_public_access_block.findings]
}

data "aws_iam_policy_document" "findings_bucket_policy" {
  # Allow GuardDuty to check bucket permissions
  statement {
    sid    = "AllowGuardDutyGetBucketLocation"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["guardduty.amazonaws.com"]
    }

    actions   = ["s3:GetBucketLocation"]
    resources = [aws_s3_bucket.findings.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  # Allow GuardDuty to write findings objects
  statement {
    sid    = "AllowGuardDutyPutObject"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["guardduty.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.findings.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  # Deny any non-HTTPS access
  statement {
    sid    = "DenyNonHttps"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [aws_s3_bucket.findings.arn, "${aws_s3_bucket.findings.arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# ---------------------------------------------------------------------------
# Publishing destination - exports findings to the S3 bucket
# ---------------------------------------------------------------------------

resource "aws_guardduty_publishing_destination" "s3" {
  detector_id      = aws_guardduty_detector.this.id
  destination_arn  = aws_s3_bucket.findings.arn
  kms_key_arn      = var.kms_key_arn
  destination_type = "S3"

  depends_on = [aws_s3_bucket_policy.findings]
}
