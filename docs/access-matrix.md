# Access Matrix: Group -> AWS Account -> Permission Set

**Account in scope:** GUDDGE LLC -- `286684483345`
**IAM Identity Center home region:** us-east-1
**Identity source:** Microsoft Entra ID (SAML login; SCIM provisions users)

> Because Entra provisions only users (not groups) in this tenant, the `aws-*` groups
> are created and managed in the AWS Identity Store (Terraform `modules/sso`), and the
> SCIM-synced users are added as members.

---

## 1. Group -> Permission Set -> Effective access

| Group (AWS-managed) | AWS Account | Permission Set       | Effective access | Session |
|---------------------|-------------|----------------------|------------------|---------|
| `aws-admins`        | 286684483345 | AdministratorAccess | Full admin (`AdministratorAccess` managed policy) | 2h |
| `aws-powerusers`    | 286684483345 | PowerUserAccess     | All services except IAM/Org management | 8h |
| `aws-developers`    | 286684483345 | Developer           | PowerUserAccess scope (compute, storage, DB, deploy) | 8h |
| `aws-readonly`      | 286684483345 | ReadOnly            | Read-only across all services | 8h |
| `aws-billing`       | 286684483345 | Billing             | Cost Management + Billing console | 8h |
| (direct)            | 286684483345 | RegionalAdmin       | Enable/disable AWS Regions only (inline policy) | 1h |

---

## 2. User -> Group mapping (target state)

| User (Entra / SCIM)      | Group        | Resulting permission set | Status  |
|--------------------------|--------------|--------------------------|---------|
| mamtaj@guddge.com        | aws-admins   | AdministratorAccess      | PENDING (not yet synced from Entra) |
| bhanua@guddge.com        | aws-admins   | AdministratorAccess      | Planned (user synced) |
| sreevatsav@guddge.com    | aws-admins   | AdministratorAccess      | CURRENT admin -- to be removed after handover |
| bhanua@guddge.com        | aws-developers | Developer              | Example mapping (adjust as needed) |
| kartikav@guddge.com      | aws-readonly | ReadOnly                 | Proposed (confirm) |
| maheshg@guddge.com       | aws-billing  | Billing                  | Proposed (confirm) |
| brucew@guddge.com        | aws-powerusers | PowerUserAccess        | Proposed (confirm) |
| guberand@guddge.com      | (to assign)  | (to assign)              | Proposed (confirm) |

> The "Proposed" rows are placeholders pending your confirmation of who belongs where.

---

## 3. Current live state (before final apply)

| Principal                     | Permission Set      | Notes |
|-------------------------------|---------------------|-------|
| "Amazon Q User" group + 1 user | AdministratorAccess | Auto-created by Amazon Q. NOT Terraform-managed. Currently grants only `q:*`/`bedrock:*` until the AdministratorAccess policy fix (PR #3) is applied. To be reviewed/removed during IAM cleanup. |
| sreevatsav@guddge.com (SSO)    | AdministratorAccess | Working SSO login; will be migrated into `aws-admins`, then removed at handover. |
| `n8n-user` (IAM user)          | n/a (IAM)           | Break-glass / automation principal. Keep until SSO admin fully verified; remove last. |

---

## 4. Machine / pipeline access (GitHub OIDC -- no human login)

| Principal (IAM role) | Trusted by | Scope |
|----------------------|-----------|-------|
| `github-deploy-dev`     | repo `main` + PRs        | Terraform manage dev resources + state |
| `github-deploy-staging` | repo `main`              | Terraform manage staging resources + state |
| `github-deploy-prod`    | repo `environment:production` | Terraform manage prod (gated on manual approval) |

> These are GitHub Actions OIDC roles, not user logins. No long-lived AWS keys.

---

## Legend
- **CURRENT** = live now. **Planned** = defined in Terraform, applies next `terraform apply`.
- **PENDING** = blocked on an external step (Entra user assignment / SCIM sync).
- **Proposed** = needs business confirmation before applying.