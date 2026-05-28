# AWS GitOps Migration -- us-west-2 (Oregon)

> **Ticket:** Migrate AWS infra to Terraform GitOps (us-west-2), enable Entra ID SSO (SAML+SCIM), and configure GitHub OIDC CI/CD.

---

## Architecture Overview

```
GitHub Repo
  Feature Branch --PR--> CI: fmt/validate/plan/security-scan
                              |-- merge to main
                              v
                         CD: apply (dev=auto, staging=auto, prod=manual approval)
                              |
                              v OIDC (no long-lived keys)
AWS us-west-2
  S3 State Bucket (SSE-KMS)  |  DynamoDB Lock  |  IAM Identity Center <-- Entra ID (SAML+SCIM)
  dev account  |  staging account  |  prod account  |  management account
```

---

## Repository Structure

| Path | Purpose |
|------|---------|
| `infra/bootstrap/` | Bootstrap module: S3 state bucket, DynamoDB lock table, KMS key, OIDC provider |
| `modules/vpc/` | VPC, subnets, route tables, NACLs, security groups, flow logs |
| `modules/iam/` | IAM deploy roles, policies, OIDC trust policies |
| `modules/s3/` | Reusable S3 bucket module with security baseline |
| `modules/kms/` | KMS keys and key policies |
| `modules/cloudtrail/` | CloudTrail multi-region trail + log bucket with object lock |
| `modules/guardduty/` | GuardDuty detector + findings export to S3 |
| `modules/sso/` | IAM Identity Center permission sets and group mappings |
| `modules/account-factory/` | (Optional) Control Tower account vending |
| `envs/dev/` | Dev environment root |
| `envs/staging/` | Staging environment root |
| `envs/prod/` | Production environment root |
| `infra/iam/` | Per-environment OIDC deploy roles |
| `.github/workflows/` | GitHub Actions workflow files |
| `.github/CODEOWNERS` | Code ownership for review enforcement |
| `ci/pr-plan.yml` | GitHub Actions: fmt/validate/plan/security-scan on PR |
| `ci/apply-dev.yml` | GitHub Actions: auto apply on merge (dev) |
| `ci/apply-staging.yml` | GitHub Actions: auto apply on merge (staging) |
| `ci/apply-prod.yml` | GitHub Actions: gated apply for prod |
| `scripts/bootstrap.md` | APPROVED manual console bootstrap steps |
| `scripts/inventory_export.sh` | Export current AWS resources to JSON |
| `scripts/generate_audit_report.sh` | Generate audit report from inventory |
| `scripts/state_migration.sh` | State import/move helper |
| `tests/smoke_dev.sh` | Smoke tests for dev |
| `tests/smoke_staging.sh` | Smoke tests for staging |
| `tests/smoke_prod.sh` | Smoke tests for prod |
| `docs/migration-checklist.md` | Resource migration checklist with risk ratings |
| `docs/rollback.md` | Rollback plan and verification checklist |
| `docs/sso-setup.md` | Entra ID SSO + SCIM configuration guide |
| `docs/oidc-setup.md` | GitHub OIDC role setup guide |
| `docs/runbook.md` | Operational runbook |
| `docs/cutover-checklist.md` | Post-migration sign-off checklist |

---

## Bootstrap Steps (Manual -- Requires Approval)

> All steps below are the **only** permitted manual console actions.
> Each must be recorded in `scripts/bootstrap.md` and signed off by Security Lead + Platform Owner.

1. Run `scripts/inventory_export.sh` and review output
2. Create S3 state bucket (`<org>-terraform-state-<account-id>`, us-west-2, SSE-KMS, versioning, access logging)
3. Create DynamoDB lock table (`terraform-state-lock`, LockID partition key, PAY_PER_REQUEST)
4. Create bootstrap IAM role (`TerraformBootstrapRole`) -- temporary, removed post-migration
5. Register GitHub OIDC provider (`https://token.actions.githubusercontent.com`)
6. Apply `infra/bootstrap/` to import pre-created resources and provision remaining bootstrap infrastructure
7. Enable IAM Identity Center in management account (one-time console action)

See `scripts/bootstrap.md` for exact click-paths and approval signatures.

---

## Required Approvals

| Action | Approver |
|--------|----------|
| Bootstrap console steps | Security Lead + Platform Owner |
| Production `terraform apply` | Platform Owner (GitHub environment gate) |
| KMS key policy changes | Security Lead |
| IAM permission set changes | Security Lead |
| SCIM credential rotation | Identity/IAM team |

---

## Correctness Properties

The following properties are enforced as static analysis checks in CI. They must hold true across all files in the repository:

| # | Property | Validation Method |
|---|----------|-------------------|
| P1 | No hardcoded region strings in Terraform resource/data blocks | `grep -r 'eu-west-2' --include='*.tf'` returns zero matches |
| P2 | No hardcoded availability zone names | `grep -r 'us-west-2[abc]' --include='*.tf'` returns zero matches |
| P3 | No secrets or credentials in source files | `truffleHog` / `git-secrets` scan; `grep -rE 'AKIA[A-Z0-9]{16}'` returns zero matches |
| P4 | All S3 buckets have public access blocked | All `aws_s3_bucket_public_access_block` resources have all four settings `true` |
| P5 | All S3 buckets and DynamoDB tables use KMS encryption | `sse_algorithm = "aws:kms"` on all buckets; KMS encryption on all DynamoDB tables |
| P6 | All stateful resources have `prevent_destroy` lifecycle | RDS, ElastiCache, EFS, S3 with replication have `lifecycle { prevent_destroy = true }` |
| P7 | Deploy role trust policies are environment-scoped | No wildcard `sub` conditions allowing cross-environment role assumption |
| P8 | No wildcard actions on sensitive services | No `iam:*`, `s3:*`, `kms:*`, or `*` in deploy role policies |
| P9 | Import blocks produce zero destructive changes | `terraform plan` after import shows no destroy/replace operations |
| P10 | CI/CD pipelines use consistent role references per environment | Same `AWS_DEPLOY_ROLE_<ENV>` secret used in both CI and CD for each environment |
| P11 | Bootstrap module is idempotent | Second `terraform plan` after apply shows zero changes |

### Running Static Analysis Checks

```bash
# Property 1: No hardcoded region strings
grep -r 'eu-west-2' modules/ envs/ infra/ --include='*.tf'

# Property 2: No hardcoded AZ names
grep -r 'us-west-2[abc]' modules/ envs/ infra/ --include='*.tf'

# Property 3: No secrets in source
grep -rE 'AKIA[A-Z0-9]{16}' .
grep -rE 'AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY' ci/ .github/ --include='*.yml'

# Property 4-8: Run tfsec/Checkov
tfsec . --soft-fail=false

# Full validation suite
terraform fmt -check -recursive
terraform validate  # (per environment with -backend=false)
```

---

## Acceptance Criteria

- [ ] All production resources represented in Terraform modules
- [ ] Terraform state in S3 + DynamoDB; no local state files
- [ ] PR pipeline: fmt/validate/plan/security-scan passes; fails on errors
- [ ] Merge to main triggers apply with required approvals
- [ ] GitHub Actions use OIDC only; zero AWS access keys in repo/logs
- [ ] Entra ID SSO: non-admin user can sign in with mapped permission set
- [ ] SCIM provisioning syncs groups and users
- [ ] MFA + conditional access enforced via Entra ID
- [ ] Branch protection: PR required, CODEOWNERS enforced, no direct pushes to main
- [ ] Security review: IAM least privilege, KMS audited, S3 encrypted and not public

---

## Estimated Milestones

| Phase | Effort |
|-------|--------|
| Inventory and export | 2-4 days |
| Repo scaffolding + modules | 3-6 days |
| State backend + bootstrap | 1 day |
| Resource conversion and import | 1-3 weeks |
| Entra SSO + SCIM mapping | 2-4 days |
| GitHub OIDC roles + workflows | 1-2 days |
| Testing, security review, cutover | 3-5 days |
