# Branch Protection Configuration

> This document describes the required GitHub branch protection settings for the `main` branch.
> These settings must be configured manually in GitHub repository settings or via the GitHub API.

---

## Branch: `main`

### Pull Request Requirements

| Setting | Value | Rationale |
|---------|-------|-----------|
| Require pull request reviews before merging | **Enabled** | All infrastructure changes must be peer-reviewed |
| Required number of approvals | **1** (minimum) | At least one team member must approve |
| Dismiss stale pull request approvals when new commits are pushed | **Enabled** | Prevents merging outdated approvals after code changes |
| Require review from Code Owners | **Enabled** | CODEOWNERS file enforces team-specific review for sensitive paths |

### Status Check Requirements

| Setting | Value | Rationale |
|---------|-------|-----------|
| Require status checks to pass before merging | **Enabled** | CI must pass before merge is allowed |
| Require branches to be up to date before merging | **Enabled** | Prevents merging stale branches that may conflict |

#### Required Status Checks

The following checks must pass before a PR can be merged. **The names below must match
exactly the job names produced by `.github/workflows/pr-plan.yml`** — GitHub uses the job
`name` as the status-check "context", and matrix jobs append the environment in parentheses.

- `Terraform Format Check` - Terraform formatting validation
- `Terraform Validate (dev)` - dev config syntax validation
- `Terraform Validate (staging)` - staging config syntax validation
- `Terraform Validate (prod)` - prod config syntax validation
- `Terraform Plan (dev)` - dev plan execution (no errors)
- `Terraform Plan (staging)` - staging plan execution (no errors)
- `Terraform Plan (prod)` - prod plan execution (no errors)
- `Security Scan (tfsec)` - tfsec security scan (fails on HIGH/CRITICAL)
- `Secret Scanning (TruffleHog)` - committed-secret detection
- `Destructive Change Check (dev)` - blocks destroy/replace without the `override-destructive` label
- `Destructive Change Check (staging)` - same gate for staging
- `Destructive Change Check (prod)` - same gate for prod

> The `Post PR Comment` job runs with `if: always()` and is informational only — do **not**
> add it as a required check.

### Push Restrictions

| Setting | Value | Rationale |
|---------|-------|-----------|
| Restrict who can push to matching branches | **Enabled** | No direct pushes allowed |
| Allow force pushes | **Disabled** | Prevents history rewriting on main |
| Allow deletions | **Disabled** | Prevents accidental branch deletion |
| Include administrators | **Enabled** | Admins are also subject to these rules - no bypass |

### Additional Settings

| Setting | Value | Rationale |
|---------|-------|-----------|
| Require linear history | **Recommended** | Keeps git history clean (squash or rebase merges) |
| Require signed commits | **Optional** | Adds commit authenticity verification |
| Lock branch | **Disabled** | Branch must remain open for PRs |

---

## GitHub Environment: `production`

In addition to branch protection, the `production` GitHub Environment provides an approval gate for prod deployments:

| Setting | Value |
|---------|-------|
| Required reviewers | Platform Owner (minimum 1 reviewer) |
| Wait timer | 0 minutes (immediate after approval) |
| Deployment branches | `main` only |

---

## Implementation

### Via GitHub UI

1. Navigate to **Settings > Branches > Branch protection rules**
2. Click **Add rule**
3. Set branch name pattern: `main`
4. Configure all settings as documented above
5. Click **Create** / **Save changes**

### Via GitHub API

```bash
gh api repos/{owner}/{repo}/branches/main/protection \
  --method PUT \
  --field required_status_checks='{"strict":true,"contexts":["Terraform Format Check","Terraform Validate (dev)","Terraform Validate (staging)","Terraform Validate (prod)","Terraform Plan (dev)","Terraform Plan (staging)","Terraform Plan (prod)","Security Scan (tfsec)","Secret Scanning (TruffleHog)","Destructive Change Check (dev)","Destructive Change Check (staging)","Destructive Change Check (prod)"]}' \
  --field enforce_admins=true \
  --field required_pull_request_reviews='{"dismiss_stale_reviews":true,"require_code_owner_reviews":true,"required_approving_review_count":1}' \
  --field restrictions=null \
  --field allow_force_pushes=false \
  --field allow_deletions=false
```

---

## Audit

Branch protection settings should be reviewed quarterly. Any changes to these settings require Security Lead approval and must be documented in this file.
