variable "alias" {
  description = "KMS key alias (without the alias/ prefix)"
  type        = string
}

variable "description" {
  description = "Description of the KMS key"
  type        = string
}

variable "deletion_window_in_days" {
  description = "Waiting period before key deletion (7-30 days)"
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30 (inclusive)."
  }
}

variable "ci_role_arns" {
  description = "List of IAM role ARNs for CI/CD that need to use this key"
  type        = list(string)
}

variable "admin_principal_arns" {
  description = "List of IAM principal ARNs that can manage this key"
  type        = list(string)
}

variable "prevent_destroy" {
  description = "Whether to set lifecycle { prevent_destroy = true } on the KMS key. Set to false only for ephemeral/test environments."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
