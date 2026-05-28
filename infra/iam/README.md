# IAM Deploy Role Architecture

This document describes the GitHub OIDC deploy role architecture used across all environments.

## Overview

Each environment (dev, staging, prod) has a dedicated IAM deploy role that GitHub Actions assumes via OIDC token exchange. No long-lived AWS access keys exist anywhere in the system.

The deploy roles are provisioned by the reusable `modules/iam/` module, called from each environment root (`envs/{dev,staging,prod}/main.tf`).

## Trust Policy Design Per Environment

All deploy roles trust the GitHub OIDC provider (`token.actions.githubusercontent.com`) with audience `sts.amazonaws.com`. The `sub` claim condition varies by environment to enforce least-privilege access:

| Environment | Role Name | `sub` Condition Operator | Allowed Subjects | Additional Conditions |
|-------------|-----------|--------------------------|------------------|-----------------------|
| dev | `github-deploy-dev` | `StringLike` | `repo:ORG/REPO:ref:refs/heads/main`, `repo:ORG/REPO:pull_request` | None |
| staging | `github-deploy-staging` | `StringLike` | `repo:ORG/REPO:ref:refs/heads/main` | None |
| prod | `github-deploy-prod` | `StringEquals` | `repo:ORG/REPO:environment:production` | `StringEquals environment = "production"` |

### Key Design Decisions

- **Dev allows `pull_request`**: Enables `terraform plan` on PRs for early feedback without requiring merge to main.
- **Staging restricts to `main` only**: No PR-based plans in staging; only merged code can assume this role.
- **Prod uses `StringEquals` (not `StringLike`)**: Prevents bypass via branch name manipulation. The `environment:production` subject format combined with the explicit `environment` condition ensures the role can only be assumed from a GitHub Actions job running in the `production` GitHub Environment (which requires human approval).

## Least-Privilege Permission Model

Each deploy role receives an inline policy (`terraform-state-access`) with explicitly enumerated actions — no wildcard (`*`) actions on `iam:*`, `s3:*`, or `kms:*`.

### State Access Permissions

All roles receive the same state access pattern, scoped to their own environment prefix:

| Permission | Resources | Purpose |
|------------|-----------|---------|
| `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket` | State bucket + `{env}/*` prefix | Read/write Terraform state |
| `dynamodb:GetItem`, `dynamodb:PutItem`, `dynamodb:DeleteItem` | Lock table | Acquire/release state lock |
| `kms:Decrypt`, `kms:GenerateDataKey`, `kms:DescribeKey` | State KMS key | Encrypt/decrypt state at rest |

### Environment-Scoped Resource Management

Additional managed policies can be attached via the `policy_arns` variable in each deploy role configuration. These should grant only the Terraform management permissions needed for that environment's resources (EC2, VPC, IAM roles with environment-scoped paths, CloudTrail, GuardDuty, KMS).

## Module Interface

The IAM module (`modules/iam/`) accepts a `deploy_roles` map:

```hcl
deploy_roles = {
  <env_key> = {
    role_name        = string       # e.g. "github-deploy-dev"
    environment_name = string       # "dev" | "staging" | "prod"
    allowed_subjects = list(string) # OIDC sub claim values
    policy_arns      = list(string) # Additional managed policy ARNs
  }
}
```

## Security Properties

1. **No cross-environment role assumption**: Each role's trust policy is scoped to specific subjects that include the environment name.
2. **No wildcard actions**: The `state_access` inline policy uses explicitly enumerated actions only.
3. **Prod requires human approval**: The `environment:production` subject and `environment` condition together enforce that only jobs running in the GitHub `production` environment (with its approval gate) can assume the prod role.
4. **OIDC-only authentication**: No `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` values exist in the repository.
