variable "trail_name" {
  type = string
}

variable "s3_bucket_name" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "prevent_destroy" {
  description = "Whether to set lifecycle { prevent_destroy = true } on the CloudTrail log bucket. Set to false only for ephemeral/test environments."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
