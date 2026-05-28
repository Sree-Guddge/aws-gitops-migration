variable "bucket_name" {
  description = "Name of the S3 bucket to create"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used for server-side encryption"
  type        = string
}

variable "log_bucket_name" {
  description = "Name of the S3 bucket to receive access logs. Set to empty string to disable logging."
  type        = string
  default     = ""
}

variable "prevent_destroy" {
  description = "Whether to set lifecycle { prevent_destroy = true } on the bucket. Set to false only for ephemeral/test buckets."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags to apply to all resources in this module"
  type        = map(string)
  default     = {}
}
