variable "bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table for state locking"
  type        = string
  default     = "terraform-state-lock"
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used for SSE on the state bucket and DynamoDB table"
  type        = string
}

variable "log_bucket_name" {
  description = "S3 bucket name for access logging"
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
