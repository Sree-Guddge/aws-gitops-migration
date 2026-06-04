# infra/sso/main.tf
# Deployable root that wires in modules/sso to manage AWS IAM Identity Center
# permission sets and group-to-account assignments.
#
# PREREQUISITES (manual, one-time -- see docs/sso-setup.md):
#   1. Enable IAM Identity Center in the management account.
#   2. Configure Entra ID as the external SAML identity provider.
#   3. Enable SCIM provisioning so Entra groups sync into the Identity Store.
#   4. Look up the synced group IDs and populate terraform.tfvars (see example).
#
# This root is applied from the management account where IAM Identity Center lives.

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Component = "sso"
      Repo      = var.github_repo
    }
  }
}

module "sso" {
  source = "../../modules/sso"

  # permission_sets uses the module default (Admin, PowerUser, ReadOnly,
  # Billing, Developer). Override here only if you need custom sets.

  account_assignments = var.account_assignments

  tags = {
    Component = "sso"
  }
}