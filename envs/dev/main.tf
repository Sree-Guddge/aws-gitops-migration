# envs/dev/main.tf
# Dev environment -- wires together all modules for the dev AWS account.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # bucket and kms_key_id are injected at init time via -backend-config flags:
    #   terraform init \
    #     -backend-config="bucket=<STATE_BUCKET_NAME>" \
    #     -backend-config="kms_key_id=<KMS_KEY_ARN>"
    key            = "dev/terraform.tfstate"
    # region injected via -backend-config flag
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = local.env
      ManagedBy   = "terraform"
      Repo        = "github.com/YOUR_ORG/aws-gitops-migration"
      CostCenter  = var.cost_center
      Owner       = var.owner_team
    }
  }
}

locals {
  env = "dev"
}

module "kms" {
  source = "../../modules/kms"

  alias       = "${local.env}-terraform-state"
  description = "KMS key for ${local.env} Terraform state and secrets"
  ci_role_arns = [
    "arn:aws:iam::${var.account_id}:role/github-deploy-${local.env}",
  ]
  admin_principal_arns = var.kms_admin_arns
  tags                 = {}
}

module "vpc" {
  source = "../../modules/vpc"

  name                 = "${local.env}-main"
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = true
  tags                 = {}
}

module "s3" {
  source = "../../modules/s3"

  bucket_name     = "${var.org_name}-app-${local.env}-${var.account_id}"
  kms_key_arn     = module.kms.key_arn
  log_bucket_name = var.log_bucket_name
  tags            = {}
}

module "cloudtrail" {
  source = "../../modules/cloudtrail"

  trail_name     = "${local.env}-trail"
  s3_bucket_name = "${var.org_name}-cloudtrail-${local.env}-${var.account_id}"
  kms_key_arn    = module.kms.key_arn
  tags           = {}
}

module "guardduty" {
  source = "../../modules/guardduty"

  findings_bucket_name = "${var.org_name}-guardduty-findings-${local.env}-${var.account_id}"
  kms_key_arn          = module.kms.key_arn
  tags                 = {}
}

module "iam" {
  source = "../../modules/iam"

  aws_region           = var.aws_region
  state_bucket_arn     = "arn:aws:s3:::${var.org_name}-tfstate-${var.account_id}"
  state_lock_table_arn = "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/terraform-state-lock"
  state_kms_key_arn    = module.kms.key_arn
  tags                 = {}

  deploy_roles = {
    dev = {
      role_name        = "github-deploy-${local.env}"
      environment_name = local.env
      allowed_subjects = [
        "repo:YOUR_ORG/aws-gitops-migration:ref:refs/heads/main",
        "repo:YOUR_ORG/aws-gitops-migration:pull_request",
      ]
      policy_arns = []
    }
  }
}
# Test: verify CI pipeline triggers on PR
# This comment was added to trigger the PR checks workflow.

