variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier (e.g. us-east-1, eu-central-1)."
  }
}

variable "account_id" {
  description = "AWS account ID for the prod environment (injected at runtime via -var or GitHub Actions secret)"
  type        = string
}

variable "org_name" {
  description = "Short organisation name used in resource naming (injected at runtime)"
  type        = string
}

variable "cost_center" {
  description = "Cost center code for billing allocation (injected at runtime)"
  type        = string
}

variable "owner_team" {
  description = "Team that owns this environment (injected at runtime)"
  type        = string
}

variable "billing_email" {
  description = "Email address to receive AWS Budgets notifications (injected at runtime)"
  type        = string
}

variable "budget_threshold" {
  description = "Monthly spend threshold in USD that triggers a budget alert"
  type        = string
  default     = "1000"
}

variable "vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.30.0.0/24", "10.30.1.0/24", "10.30.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.30.10.0/24", "10.30.11.0/24", "10.30.12.0/24"]
}

variable "kms_admin_arns" {
  description = "IAM principal ARNs that can manage KMS keys"
  type        = list(string)
}

variable "log_bucket_name" {
  description = "Name of the S3 bucket to receive access logs (from bootstrap output: log_bucket_name)"
  type        = string
}
