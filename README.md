# AWS GitOps Migration -- us-west-2 (Oregon)

> **Ticket:** Migrate AWS infra to Terraform GitOps (us-west-2), enable Entra ID SSO (SAML+SCIM), and configure GitHub OIDC CI/CD.

---

## Architecture Overview

```
GitHub Repo
  Feature Branch --PR--> CI: fmt/validate/plan
                              |-- merge to main
                              v
                         CD: apply (dev=auto, prod=manual approval)
                              |
                              v OIDC (no long-lived keys)
AWS us-west-2
  S3 State Bucket (SSE-KMS)  |  DynamoDB Lock  |  IAM Identity Center <-- Entra ID (SAML+SCIM)
  dev account  |  staging account  |  prod account  |  management account

Directory Layout:
  infra/bootstrap/       --> S3 state, DynamoDB lock, OIDC provider, KMS
  infra/deploy-roles/    --> Per-environment OIDC deploy roles
  modules/vpc/           --> VPC, subnets, route tables, NACLs, SGs
  modules/s3/            --> Reusable S3 bucket module
  envs/{dev,staging,prod}/ --> Environment root configurations
  .github/workflows/     --> CI/CD pipeline definitions
```

---

## Repository Structure

| Path | Purpose |
|------|---------|
| `infra/bootstrap/` | Bootstrap module: S3 state bucket, DynamoDB lock table, OIDC provider, KMS key |
| `infra/deploy-roles/` | OIDC deploy roles per environment (dev, staging, prod) |
| `infra/sso/` | Deployable IAM Identity Center root: permission sets + Entra group assignments |
| `modules/vpc/` | VPC, subnets, route tables, NACLs, security groups |
| `modules/s3/` | Reusable S3 bucket module with enforced security baseline |
| `modules/iam/` | IAM roles, policies, OIDC provider |
| `modules/kms/` | KMS keys and key policies |
| `modules/cloudtrail/` | CloudTrail multi-region trail |
| `modules/guardduty/` | GuardDuty detector + findings export |
| `modules/sso/` | IAM Identity Center permission sets and group mappings |
| `modules/account-factory/` | (Optional) Control Tower account vending |
| `envs/dev/` | Dev environment overlay |
| `envs/staging/` | Staging environment overlay |
| `envs/prod/` | Production environment overlay |
| `.github/workflows/pr-plan.yml` | PR pipeline: fmt/validate/plan + tfsec + secret-scan + destructive-check + PR comment (OIDC) |
| `.github/workflows/apply-dev.yml` | GitHub Actions: auto apply on merge (dev) |
| `.github/workflows/apply-staging.yml` | GitHub Actions: auto apply on merge (staging) |
| `.github/workflows/apply-prod.yml` | GitHub Actions: gated apply for prod (production environment approval) |
| `.github/workflows/inventory-export.yml` | GitHub Actions: AWS resource inventory export |
| `.github/CODEOWNERS` | Code ownership for branch protection enforcement |
| `scripts/bootstrap.md` | APPROVED manual console bootstrap steps |
| `scripts/inventory_export.sh` | Export current AWS resources to JSON/CSV |
| `scripts/state_migration.sh` | State import/move helper |
| `tests/smoke_dev.sh` | Smoke tests for dev |
| `tests/smoke_staging.sh` | Smoke tests for staging |
| `tests/smoke_prod.sh` | Smoke tests for prod |
| `docs/migration-checklist.md` | Per-resource migration checklist with risk ratings |
| `docs/rollback.md` | Rollback plan and verification checklist |
| `docs/sso-setup.md` | Entra ID SSO + SCIM configuration guide |
| `docs/oidc-setup.md` | GitHub OIDC role setup guide |
| `docs/runbook.md` | Operational runbook |
| `docs/cutover-checklist.md` | Post-migration sign-off checklist |

---

## Bootstrap Steps (Manual -- Requires Approval)

> All steps below are the **only** permitted manual console actions.
> Each must be recorded in `scripts/bootstrap.md` and signed off by Security Lead + Platform Owner.

1. Create S3 state bucket (`<org>-terraform-state-<account-id>`, us-west-2, SSE-KMS, versioning, access logging)
2. Create DynamoDB lock table (`terraform-state-lock`, LockID partition key, PAY_PER_REQUEST)
3. Create bootstrap IAM role (`TerraformBootstrapRole`) -- temporary, removed post-migration
4. Register GitHub OIDC provider (`https://token.actions.githubusercontent.com`)
5. Enable IAM Identity Center in management account (one-time console action)

See `scripts/bootstrap.md` for exact click-paths and approval signatures.

After manual pre-creation, run the bootstrap module to import and manage these resources:

```bash
cd infra/bootstrap/
terraform init
terraform plan
terraform apply
```

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

## Correctness Properties and Static Analysis

The following properties must hold across the entire repository. Each can be verified with the listed commands. These checks run as part of the CI pipeline and can be executed locally.

### Property 1: Zero `us-west-2` references in any .tf or .yml file

All region references must use `var.aws_region` -- no hardcoded legacy region strings.

```bash
grep -r 'us-west-2' --include='*.tf' --include='*.yml' --include='*.tfvars' .
```

**Expected result:** zero matches.

### Property 2: Zero hardcoded Availability Zone names

AZs must be resolved via `data "aws_availability_zones"` -- no literal `us-west-2a/b/c`.

```bash
grep -r 'us-west-2[abc]' --include='*.tf' .
```

**Expected result:** zero matches.

### Property 3: Zero hardcoded AWS access keys

No credentials committed to source -- all secrets injected at runtime.

```bash
grep -rE 'AKIA[A-Z0-9]{16}' .
grep -r 'AWS_ACCESS_KEY_ID\|AWS_SECRET_ACCESS_KEY' .github/workflows/ --include='*.yml'
```

**Expected result:** zero matches for both commands.

### Property 4: All CI/CD workflows use OIDC

Every workflow that authenticates to AWS must use `aws-actions/configure-aws-credentials@v4` with `role-to-assume` -- no static credentials.

```bash
grep -r 'aws-actions/configure-aws-credentials' --include='*.yml' . | grep -v 'role-to-assume'
```

**Expected result:** zero matches (every usage includes `role-to-assume`).

### Running All Checks

To run all static analysis checks at once:

```bash
echo "=== Property 1: No us-west-2 references ==="
grep -r 'us-west-2' --include='*.tf' --include='*.yml' --include='*.tfvars' . && echo "FAIL" || echo "PASS"

echo "=== Property 2: No hardcoded AZ names ==="
grep -r 'us-west-2[abc]' --include='*.tf' . && echo "FAIL" || echo "PASS"

echo "=== Property 3: No hardcoded AWS access keys ==="
grep -rE 'AKIA[A-Z0-9]{16}' . && echo "FAIL" || echo "PASS"
grep -r 'AWS_ACCESS_KEY_ID\|AWS_SECRET_ACCESS_KEY' .github/workflows/ --include='*.yml' && echo "FAIL" || echo "PASS"

echo "=== Property 4: All workflows use OIDC ==="
grep -r 'aws-actions/configure-aws-credentials' --include='*.yml' . | grep -v 'role-to-assume' && echo "FAIL" || echo "PASS"
```

---

## Acceptance Criteria

- [ ] All production resources represented in Terraform modules
- [ ] Terraform state in S3 + DynamoDB; no local state files
- [ ] PR pipeline: fmt/validate/plan passes; fails on errors
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
