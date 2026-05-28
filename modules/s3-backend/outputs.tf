output "bucket_id" {
  description = "ID of the Terraform state S3 bucket"
  value       = aws_s3_bucket.state.id
}

output "bucket_arn" {
  description = "ARN of the Terraform state S3 bucket"
  value       = aws_s3_bucket.state.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB lock table"
  value       = aws_dynamodb_table.lock.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB lock table"
  value       = aws_dynamodb_table.lock.arn
}
