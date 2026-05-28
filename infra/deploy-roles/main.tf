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
  region = "us-west-2"
}

locals {
  oidc_arn         = "arn:aws:iam::286684483345:oidc-provider/token.actions.githubusercontent.com"
  repo             = "Sree-Guddge/aws-gitops-migration"
  state_bucket_arn = "arn:aws:s3:::sree-guddge-terraform-state-286684483345"
  lock_table_arn   = "arn:aws:dynamodb:us-west-2:286684483345:table/terraform-state-lock"
  kms_key_arn      = "arn:aws:kms:us-west-2:286684483345:key/8ad71d07-ef24-47d2-8c9d-b3d86e4fee6d"
}

resource "aws_iam_role" "dev" {
  name = "github-deploy-dev"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = ["repo:${local.repo}:ref:refs/heads/main", "repo:${local.repo}:pull_request"] }
      }
    }]
  })
  tags = { Environment = "dev", ManagedBy = "terraform" }
}

resource "aws_iam_role" "staging" {
  name = "github-deploy-staging"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = ["repo:${local.repo}:ref:refs/heads/main"] }
      }
    }]
  })
  tags = { Environment = "staging", ManagedBy = "terraform" }
}

resource "aws_iam_role" "prod" {
  name = "github-deploy-prod"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${local.repo}:environment:production"
        }
      }
    }]
  })
  tags = { Environment = "prod", ManagedBy = "terraform" }
}

resource "aws_iam_role_policy" "dev_state" {
  name = "terraform-state-access"
  role = aws_iam_role.dev.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket"], Resource = [local.state_bucket_arn, "${local.state_bucket_arn}/dev/*"] },
      { Effect = "Allow", Action = ["dynamodb:GetItem","dynamodb:PutItem","dynamodb:DeleteItem"], Resource = [local.lock_table_arn] },
      { Effect = "Allow", Action = ["kms:Decrypt","kms:GenerateDataKey","kms:DescribeKey"], Resource = [local.kms_key_arn] }
    ]
  })
}

resource "aws_iam_role_policy" "staging_state" {
  name = "terraform-state-access"
  role = aws_iam_role.staging.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket"], Resource = [local.state_bucket_arn, "${local.state_bucket_arn}/staging/*"] },
      { Effect = "Allow", Action = ["dynamodb:GetItem","dynamodb:PutItem","dynamodb:DeleteItem"], Resource = [local.lock_table_arn] },
      { Effect = "Allow", Action = ["kms:Decrypt","kms:GenerateDataKey","kms:DescribeKey"], Resource = [local.kms_key_arn] }
    ]
  })
}

resource "aws_iam_role_policy" "prod_state" {
  name = "terraform-state-access"
  role = aws_iam_role.prod.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket"], Resource = [local.state_bucket_arn, "${local.state_bucket_arn}/prod/*"] },
      { Effect = "Allow", Action = ["dynamodb:GetItem","dynamodb:PutItem","dynamodb:DeleteItem"], Resource = [local.lock_table_arn] },
      { Effect = "Allow", Action = ["kms:Decrypt","kms:GenerateDataKey","kms:DescribeKey"], Resource = [local.kms_key_arn] }
    ]
  })
}

output "dev_role_arn" { value = aws_iam_role.dev.arn }
output "staging_role_arn" { value = aws_iam_role.staging.arn }
output "prod_role_arn" { value = aws_iam_role.prod.arn }
