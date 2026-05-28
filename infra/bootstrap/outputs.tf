# infra/bootstrap/outputs.tf
# Exports key identifiers from the bootstrap module for use by environment roots
# and CI/CD pipelines (injected via -backend-config flags or GitHub Actions secrets).

output "state_bucket_name" {
  description = "Name of the S3 bucket used to store Terraform remote state."
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket used to store Terraform remote state."
  value       = aws_s3_bucket.state.arn
}

output "state_lock_table_arn" {
  description = "ARN of the DynamoDB table used for Terraform state locking."
  value       = aws_dynamodb_table.lock.arn
}

output "state_kms_key_arn" {
  description = "ARN of the KMS key used to encrypt the state bucket and DynamoDB lock table."
  value       = aws_kms_key.state.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider used by deploy roles."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "log_bucket_name" {
  description = "Name of the S3 bucket used for state bucket access logs."
  value       = aws_s3_bucket.logs.id
}
