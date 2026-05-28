output "bucket_id" {
  description = "The name (ID) of the S3 bucket"
  value       = local.bucket_id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = local.bucket_arn
}

output "bucket_domain_name" {
  description = "The bucket domain name (bucket-name.s3.amazonaws.com)"
  value       = var.prevent_destroy ? aws_s3_bucket.this[0].bucket_domain_name : aws_s3_bucket.this_unprotected[0].bucket_domain_name
}
