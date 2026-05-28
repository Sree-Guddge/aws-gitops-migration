variable "findings_bucket_name" {
  description = "Name of the S3 bucket to create for GuardDuty findings export"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN used to encrypt the findings bucket and GuardDuty findings"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources in this module"
  type        = map(string)
  default     = {}
}
