# infra/bootstrap/variables.tf
# Input variables for the bootstrap module.
# All sensitive values (bucket names, account IDs) are supplied at runtime
# via -var flags or GitHub Actions secrets -- never committed to source.

variable "aws_region" {
  description = "AWS region to deploy bootstrap resources into."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier (e.g. us-west-2, eu-central-1)."
  }
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket used for Terraform remote state. Must be globally unique."
  type        = string
}

variable "log_bucket_name" {
  description = "Name of the S3 bucket used for state bucket access logs. Must be globally unique."
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking."
  type        = string
  default     = "terraform-state-lock"
}

variable "kms_key_deletion_window" {
  description = "Waiting period in days before the KMS key is deleted (7-30)."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "kms_key_deletion_window must be between 7 and 30 days."
  }
}

variable "bootstrap_role_arn" {
  description = "ARN of the temporary bootstrap IAM role used for the initial apply. Added to the KMS key policy."
  type        = string
  default     = ""
}

variable "deploy_role_arns" {
  description = "List of IAM role ARNs for GitHub Actions deploy roles that need KMS usage permissions. Populated after Task 19."
  type        = list(string)
  default     = []
}

variable "github_oidc_thumbprints" {
  description = "List of server certificate thumbprints for the GitHub OIDC provider. Update when GitHub rotates their certificate."
  type        = list(string)
  # Current GitHub Actions OIDC thumbprints (as of 2024).
  # Source: https://github.blog/changelog/2023-06-27-github-actions-update-on-oidc-integration-with-aws/
  default = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

variable "tags" {
  description = "Additional tags applied to all bootstrap resources."
  type        = map(string)
  default     = {}
}
