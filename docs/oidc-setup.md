# GitHub OIDC Role Setup Guide

## Overview

GitHub Actions uses OIDC (OpenID Connect) to assume AWS IAM roles without storing long-lived credentials.
Each environment has a dedicated deploy role scoped to the specific repo and branch/environment.

---

## How It Works

1. GitHub Actions requests a short-lived OIDC token from GitHub
2. The token is exchanged for temporary AWS credentials via sts:AssumeRoleWithWebIdentity
3. The IAM role trust policy validates the token claims (repo, branch, environment)
4. Credentials expire after the session duration (max 1 hour for CI)

---

## IAM Role Trust Policy Structure

Each deploy role has a trust policy like this:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/aws-gitops-migration:environment:prod"
        }
      }
    }
  ]
}
```

The sub claim format options:
- Specific environment: repo:ORG/REPO:environment:prod
- Specific branch: repo:ORG/REPO:ref:refs/heads/main
- Any branch (dev only): repo:ORG/REPO:*

---

## GitHub Secrets Required

Configure these secrets in your GitHub repository (Settings > Secrets > Actions):

| Secret name | Value |
|-------------|-------|
| AWS_DEPLOY_ROLE_DEV | arn:aws:iam::DEV_ACCOUNT_ID:role/github-deploy-dev |
| AWS_DEPLOY_ROLE_STAGING | arn:aws:iam::STAGING_ACCOUNT_ID:role/github-deploy-staging |
| AWS_DEPLOY_ROLE_PROD | arn:aws:iam::PROD_ACCOUNT_ID:role/github-deploy-prod |

No AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY should ever be stored.

---

## GitHub Environments Configuration

Configure GitHub Environments (Settings > Environments):

### dev environment
- No required reviewers (auto-apply)
- No wait timer

### staging environment
- Optional: 1 required reviewer

### prod environment
- Required reviewers: Platform Owner (mandatory)
- Wait timer: 5 minutes (gives time to cancel)
- Deployment branches: main only

---

## Terraform Module Usage

The modules/iam module creates the OIDC provider and deploy roles.
Example configuration in envs/prod/main.tf:

```hcl
module "iam" {
  source = "../../modules/iam"

  deploy_roles = {
    prod = {
      role_name = "github-deploy-prod"
      allowed_subjects = [
        "repo:YOUR_ORG/aws-gitops-migration:environment:prod"
      ]
      policy_arns = [
        "arn:aws:iam::aws:policy/ReadOnlyAccess",
        # Add specific permissions needed for Terraform apply
      ]
    }
  }

  state_bucket_arn     = "arn:aws:s3:::ORGNAME-terraform-state-ACCOUNT_ID"
  state_lock_table_arn = "arn:aws:dynamodb:eu-west-2:ACCOUNT_ID:table/terraform-state-lock"
  state_kms_key_arn    = "arn:aws:kms:eu-west-2:ACCOUNT_ID:key/KEY_ID"
}
```

---

## Verification

After deploying the OIDC provider and roles, verify with a test workflow:

```yaml
- name: Configure AWS credentials via OIDC
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_DEV }}
    aws-region: eu-west-2

- name: Verify identity
  run: aws sts get-caller-identity
```

The output should show the assumed role ARN, not an IAM user.
Verify no AccessKeyId appears in the logs (GitHub masks secrets but OIDC tokens are not stored).
