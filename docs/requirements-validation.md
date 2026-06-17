# Requirements Validation — AWS GitOps Migration (us-west-2)

> Validation of the repository against the project brief (move AWS to Terraform/GitOps,
> Entra ID SSO, GitHub OIDC). Findings are based on the actual code and live checks
> (`terraform validate`/`fmt`, `grep`), not the spec task checkboxes.
>
> **Validated:** 2026-06-18

---

## Verdict

The **IaC + OIDC workstreams are built and code-verified**, and the **region goal is met**
(zero `eu-west-2`, region injected at runtime, all four roots validate clean). The remaining
gaps are all in the "live data + external-system + cleanup" category: the inventory/import
blocks are templates with placeholder IDs, the Entra-side proofs are not evidenced in-repo,
and the GitHub branch-protection / environment settings are documented but applied outside
the repo.

Legend: ✅ done & verified in-repo · 🟡 partial / templated / pending · 📄 documented only
(external system) · ⚠️ issue to fix

---

## 1. Move AWS setup to Git / IaC

| Req | Status | Evidence / note |
|---|---|---|
| 1. Repo structure | ✅ | `infra/`, `modules/` (vpc, s3, kms, iam, cloudtrail, guardduty, sso, account-factory), `envs/{dev,staging,prod}`, `.github/`, `docs/`, `scripts/`, `tests/` |
| 2. Export/document current AWS (accounts, IAM, VPC, SG, S3, CloudTrail, GuardDuty, budgets) | 🟡 | `scripts/inventory_export.sh` + `generate_audit_report.sh` exist; `docs/audit-report.md` header says "Generated: PENDING" and lists resource *types*, not live IDs. Capability built; live capture not run. |
| 3. Convert existing resources to Terraform | ✅ code / 🟡 imports | All modules implemented and validate clean. `envs/dev/imports.tf` import blocks use placeholder IDs (`vpc-XXXXXXXXXX`). `infra/bootstrap/main.tf` went greenfield ("import block removed for fresh deployment") while env imports are brownfield-templated — pick one path. |
| 4. State in S3 + DynamoDB lock | ✅ | `infra/bootstrap/main.tf`: S3 (SSE-KMS, versioning, public-access-block ×4, access logging, lifecycle, `prevent_destroy`) + DynamoDB (`LockID`, PAY_PER_REQUEST, SSE-KMS, PITR, `prevent_destroy`) + KMS w/ rotation |
| 5. Branch rules (PR required, no direct push) | 📄 / ⚠️ | `.github/branch-protection.md` + `CODEOWNERS` are thorough, but enforcement is a GitHub setting applied outside the repo. Required-check names were fixed to match real job names (see that doc). `@platform-team`/`@security-team` must exist as GitHub teams. |
| 6. CI/CD (PR=fmt/validate/plan; merge=apply after approval) | ✅ | `.github/workflows/pr-plan.yml`: fmt + validate + plan + tfsec + TruffleHog + destructive-check + PR comment. `apply-dev`/`apply-staging` auto-apply; `apply-prod` has `environment: production` approval gate. |
| 7. No AWS keys in Git; OIDC | ✅ | 0 `AKIA…` in repo; 16/16 `configure-aws-credentials` use `role-to-assume`; OIDC provider in bootstrap |
| (opt) Account Factory for Terraform | ✅ | `modules/account-factory/` present |

---

## 2. Entra ID as AWS IAM provider

| Req | Status | Evidence / note |
|---|---|---|
| 1. Enable IAM Identity Center | ✅ (live) | Identity store `d-90663e376f` exists (`docs/access-matrix.md`); one-time console action, not Terraform-managed by design |
| 2. Add AWS enterprise app in Entra | 📄 | `docs/sso-setup.md` Part 1.1 — external Entra config |
| 3. Configure SAML SSO | 📄 | `sso-setup.md` Part 1; an admin SSO login works live |
| 4. Enable SCIM provisioning | 📄 / 🟡 | `sso-setup.md` Part 2. Documented constraint: this tenant syncs users only, not groups → groups created in AWS via Terraform (`modules/sso` `aws_identitystore_group`). |
| 5. Permission sets (Admin, PowerUser, ReadOnly, Billing, Developer) | ✅ | `modules/sso/variables.tf` defaults define all 5 (`AdministratorAccess`, `PowerUserAccess`, `ReadOnly`, `Billing`, `Developer`) plus `RegionalAdmin` |
| 6. Map Entra groups → accounts → permission sets | ✅ code / 🟡 data | `infra/sso/terraform.tfvars` maps `aws-admins`→AdministratorAccess, `aws-developers`→Developer on `286684483345`. Only `sreevatsav`+`bhanua` populated; `mamtaj` pending sync. |
| 7. Test login with one non-admin user | 🟡 not evidenced | `access-matrix.md` marks non-admin rows "Proposed (confirm)". Only an admin login is confirmed. |
| 8. Enforce MFA + conditional access | 📄 | `sso-setup.md` Part 4 — external Entra policy |
| 9. Remove direct IAM users | 🟡 deferred | By design: `n8n-user` kept as break-glass "removed last"; "Amazon Q User" group flagged for review. |

---

## 3. GitHub Actions OIDC

| Req | Status | Evidence / note |
|---|---|---|
| 1. AWS IAM OIDC provider for GitHub | ✅ | `aws_iam_openid_connect_provider.github` in bootstrap |
| 2. Deploy roles per environment | ✅ | `infra/deploy-roles/main.tf`: `github-deploy-dev/staging/prod` with scoped least-priv state policies |
| 3. Trust only repo/branch/environment | ✅ | dev = `main` + `pull_request`; staging = `main`; prod = `StringEquals …:environment:production` |
| 4. Workflow assumes role + runs Terraform | ✅ | all apply/plan workflows use `configure-aws-credentials@v4` + `role-to-assume` |
| 5. Prod apply requires approval | ✅ | `apply-prod.yml` apply job: `environment: production` gate |

---

## Demo deliverables (8)

All eight have artifacts: architecture diagram + repo structure (`README.md`, `handover-guide.md`
§1–2), Terraform code (validated), Identity Center/Entra doc (`sso-setup.md`), GitHub Actions
(`pr-plan.yml` + `apply-*`), rollback plan (`rollback.md`, 4 phases), access matrix
(`access-matrix.md`), and the handover demo script (`handover-guide.md` §8 + `docs/demo-prep.md`). ✅

---

## Hard evidence collected

- `terraform validate` → **Success** on `envs/dev`, `envs/staging`, `envs/prod`, `infra/bootstrap` (all exit 0)
- `terraform fmt -check -recursive` → passes
- `grep` → 0 `eu-west-2`, 0 hardcoded `us-west-2`, 0 `us-west-2[abc]` AZ literals, 0 `AKIA…` in the repo
- OIDC → 16/16 `configure-aws-credentials` steps paired with `role-to-assume`

---

## Outstanding before claiming 100%

1. **Run the live inventory + fill `imports.tf`** with real resource IDs (or explicitly declare this a greenfield build and remove/relabel the brownfield import templates + the "PENDING" audit report).
2. **Perform and capture a non-admin SSO login** (req 2.7) — e.g. a `ReadOnly`/`Developer` user.
3. **Apply the GitHub settings** (branch protection, `production` environment reviewers, `@platform-team`/`@security-team`); the required-check names now match the real job names.
4. **Finish the admin cutover prerequisite** — `mamtaj@guddge.com` synced from Entra (`admin-handover.md`).
5. **Confirm MFA/conditional-access** is live in Entra (req 2.8).
6. **Cleanup (done):** duplicate `ci/` workflows and the redundant `pr-checks.yml` removed; `pr-plan.yml` is the single PR pipeline.

Items 1–5 are evidence/external-action, not missing code. The code for all three workstreams is implemented and validates clean.
