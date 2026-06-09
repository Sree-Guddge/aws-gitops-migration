variable "aws_region" {
  description = "Home region of the IAM Identity Center instance. NOTE: this is the SSO home region (us-east-1), which may differ from the workload region. IAM Identity Center cannot be relocated to match workloads."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier (e.g., us-east-1)."
  }
}

variable "github_repo" {
  description = "GitHub repository (org/repo) for tagging"
  type        = string
  default     = "Sree-Guddge/aws-gitops-migration"
}

variable "account_assignments" {
  description = "List of group-to-account-to-permission-set mappings. group_id values come from the Entra ID SCIM-synced Identity Store groups (see docs/sso-setup.md Part 3)."
  type = list(object({
    group_id       = string
    account_id     = string
    permission_set = string
  }))
  default = []

  validation {
    condition = alltrue([
      for a in var.account_assignments :
      contains(["AdministratorAccess", "PowerUserAccess", "ReadOnly", "Billing", "Developer", "RegionalAdmin"], a.permission_set)
    ])
    error_message = "permission_set must be one of: AdministratorAccess, PowerUserAccess, ReadOnly, Billing, Developer, RegionalAdmin."
  }

  validation {
    condition = alltrue([
      for a in var.account_assignments : can(regex("^[0-9]{12}$", a.account_id))
    ])
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
variable "managed_groups" {
  description = "AWS-managed Identity Store groups: group display name -> list of usernames (e.g. \"user@guddge.com\"). Needed because Entra only provisions users, not groups."
  type        = map(list(string))
  default     = {}
}

variable "managed_group_assignments" {
  description = "Assignments mapping an AWS-managed group (display name) to an account + permission set."
  type = list(object({
    group_name     = string
    account_id     = string
    permission_set = string
  }))
  default = []

  validation {
    condition = alltrue([
      for a in var.managed_group_assignments :
      contains(["AdministratorAccess", "PowerUserAccess", "ReadOnly", "Billing", "Developer", "RegionalAdmin"], a.permission_set)
    ])
    error_message = "permission_set must be one of: AdministratorAccess, PowerUserAccess, ReadOnly, Billing, Developer, RegionalAdmin."
  }
}
