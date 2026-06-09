# infra/iam/dev/variables.tf
# Variables for the dev environment deploy role.
# Sensitive values (account_id, state_bucket_name) are injected at runtime
# via -var flags or GitHub Actions secrets -- never hardcoded.

variable "aws_region" {
  description = "AWS region for this deployment"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier (e.g. us-east-1)."
  }
}

variable "account_id" {
  description = "AWS account ID where the deploy role is created (injected at runtime)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "github_org" {
  description = "GitHub organization name (e.g. 'my-org')"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (e.g. 'aws-gitops-migration')"
  type        = string
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket used for Terraform state (injected at runtime)"
  type        = string
}

variable "state_lock_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking"
  type        = string
  default     = "terraform-state-lock"
}

variable "state_kms_key_arn" {
  description = "ARN of the KMS key used to encrypt Terraform state (injected at runtime)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider (from bootstrap module output)"
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
