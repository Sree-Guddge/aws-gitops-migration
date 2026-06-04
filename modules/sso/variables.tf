variable "permission_sets" {
  description = "Map of permission set name to configuration. Defaults match the permission sets currently provisioned in the live IAM Identity Center instance."
  type = map(object({
    description         = string
    session_duration    = string # ISO 8601, e.g. "PT8H"
    managed_policy_arns = list(string)
    inline_policy       = optional(string)
    relay_state         = optional(string)
  }))
  default = {
    # NOTE: the live "AdministratorAccess" permission set has NO managed policy attached --
    # only the inline Amazon Q/Bedrock policy below. Matched as-is to avoid drift.
    # See the access-review note in docs/sso-setup.md before changing this.
    AdministratorAccess = {
      description         = "Full administrative access"
      session_duration    = "PT2H"
      managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      inline_policy       = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"AmazonQDeveloperFreeTrialAccess\",\"Effect\":\"Allow\",\"Action\":[\"q:*\",\"bedrock:*\"],\"Resource\":\"*\"}]}"
    }
    PowerUserAccess = {
      description         = "Power user access (no IAM)"
      session_duration    = "PT8H"
      managed_policy_arns = ["arn:aws:iam::aws:policy/PowerUserAccess"]
    }
    ReadOnly = {
      description         = "Read-only access to all AWS services"
      session_duration    = "PT8H"
      managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    }
    Billing = {
      description         = "Billing and cost management access"
      session_duration    = "PT8H"
      managed_policy_arns = ["arn:aws:iam::aws:policy/job-function/Billing"]
    }
    Developer = {
      description         = "Developer access - compute, storage, databases, deployment services"
      session_duration    = "PT8H"
      managed_policy_arns = ["arn:aws:iam::aws:policy/PowerUserAccess"]
    }
    RegionalAdmin = {
      description         = "Manage which AWS regions are enabled for the account"
      session_duration    = "PT1H"
      managed_policy_arns = []
      inline_policy       = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"Statement1\",\"Effect\":\"Allow\",\"Action\":[\"account:ListRegions\",\"account:DisableRegion\",\"account:EnableRegion\",\"account:GetRegionOptStatus\"],\"Resource\":[\"*\"]}]}"
    }
  }
}

variable "account_assignments" {
  description = "List of group-to-account-to-permission-set mappings"
  type = list(object({
    group_id       = string # Identity Store group ID (from Entra SCIM sync)
    account_id     = string # AWS account ID
    permission_set = string # Key from permission_sets map
  }))
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
