variable "aws_region" {
  description = "AWS region for this module"
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier (e.g. us-west-2, eu-west-1)."
  }
}

variable "github_oidc_thumbprints" {
  description = "Thumbprint list for GitHub OIDC provider"
  type        = list(string)
  # Current thumbprint as of 2024 -- verify at https://github.blog/changelog/
  default = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

variable "deploy_roles" {
  description = "Map of environment name to deploy role configuration"
  type = map(object({
    role_name        = string
    environment_name = string       # logical environment label: dev | staging | prod
    allowed_subjects = list(string) # e.g. ["repo:myorg/myrepo:environment:prod"]
    policy_arns      = list(string)
  }))
}

variable "state_bucket_arn" {
  description = "ARN of the Terraform state S3 bucket"
  type        = string
}

variable "state_lock_table_arn" {
  description = "ARN of the DynamoDB state lock table"
  type        = string
}

variable "state_kms_key_arn" {
  description = "ARN of the KMS key used for state encryption"
  type        = string
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
