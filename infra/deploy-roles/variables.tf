variable "aws_region" {
  description = "AWS region for deploy role resources"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier (e.g. us-east-1)."
  }
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without org prefix)"
  type        = string
}

variable "account_id" {
  description = "AWS account ID where deploy roles are created"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket used for Terraform state"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt Terraform state"
  type        = string
}
