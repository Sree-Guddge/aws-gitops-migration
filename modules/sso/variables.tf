variable "permission_sets" {
  description = "Map of permission set name to configuration"
  type = map(object({
    description         = string
    session_duration    = string # ISO 8601, e.g. "PT8H"
    managed_policy_arns = list(string)
    inline_policy       = optional(string)
    relay_state         = optional(string)
  }))
  default = {
    Admin = {
      description         = "Full administrative access"
      session_duration    = "PT4H"
      managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    }
    PowerUser = {
      description         = "Power user access (no IAM)"
      session_duration    = "PT8H"
      managed_policy_arns = ["arn:aws:iam::aws:policy/PowerUserAccess"]
    }
    ReadOnly = {
      description         = "Read-only access to all services"
      session_duration    = "PT8H"
      managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    }
    Billing = {
      description         = "Billing and cost management access"
      session_duration    = "PT8H"
      managed_policy_arns = ["arn:aws:iam::aws:policy/job-function/Billing"]
    }
    Developer = {
      description      = "Developer access (EC2, ECS, Lambda, S3, RDS, CloudWatch)"
      session_duration = "PT8H"
      managed_policy_arns = [
        "arn:aws:iam::aws:policy/AmazonEC2FullAccess",
        "arn:aws:iam::aws:policy/AWSLambda_FullAccess",
        "arn:aws:iam::aws:policy/AmazonS3FullAccess",
        "arn:aws:iam::aws:policy/CloudWatchFullAccess",
      ]
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
