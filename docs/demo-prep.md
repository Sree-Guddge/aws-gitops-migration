# Demo Prep Guide — AWS GitOps Handover Call

> Working prep notes for the final handover call. The run-of-show mirrors Section 8 of
> `docs/handover-guide.md`. Every "this passes live" claim below was verified against the
> real repo, not assumed.

---

## TL;DR — verified state of the repo

These are the actual checks the demo relies on, run against this repo:

| Check (what the demo claims) | Real result | Live-demo safe? |
|---|---|---|
| `terraform fmt -check -recursive` | Was failing on 3 env files → fixed (commit `fe442c1`) | Yes |
| No legacy `eu-west-2` in `.tf/.yml/.tfvars` | 0 matches | Yes |
| No hardcoded `us-west-2` (region injected at runtime) | 0 matches | Yes |
| No hardcoded AZ names (`us-west-2a/b/c`) | 0 matches | Yes |
| No AWS access keys (`AKIA…`) in the repo | 0 matches | Yes |
| Every workflow AWS auth uses OIDC `role-to-assume` | 16 / 16 | Yes |
| Terraform / AWS CLI / GitHub CLI installed | all present | Yes |
| `tfsec`, `checkov`, `jq` installed | missing | See landmines |

Run all of these in one shot any time with:

```powershell
pwsh -File scripts/preflight.ps1      # or: powershell -ExecutionPolicy Bypass -File scripts/preflight.ps1
```

---

## Part 1 — The night before

**Step 1. Open a terminal at the repo root.**

```
cd c:\Users\jyoth\.kiro\aws-gitops-migration
```

**Step 2. Confirm the repo is clean.**
The `terraform fmt` fix is already committed (`fe442c1`). `git status` should show only the
two intentionally-untracked files (`docs/handover-guide.md`, `infra/sso/terraform.tfvars`).
A messy `git status` mid-demo invites distracting questions.

**Step 3. Run the preflight script once so you've seen the green output.**

```powershell
pwsh -File scripts/preflight.ps1
```

Everything except the tool-availability line should report PASS.

**Step 4. Decide live-vs-recorded for the two risky demos.**
- Demo 2 (PR → deploy): decide whether you'll do a real apply to **dev**, or stop at the
  **plan / PR-comment** (safer). Recommended: stop at plan unless dev is disposable.
- Demo 3 (SSO login): confirm the portal URL works in incognito tonight —
  `https://d-90663e376f.awsapps.com/start`. Have a test user + MFA device ready.

**Step 5. Verify the critical-path item: the admin handover.**
`docs/admin-handover.md` makes sign-off depend on `mamtaj@guddge.com` logging in, but
`infra/sso/terraform.tfvars` currently lists only `sreevatsav` and `bhanua`. Confirm whether
mamtaj is synced:

```powershell
aws identitystore list-users --region us-east-1 --identity-store-id d-90663e376f --query "Users[?UserName=='mamtaj@guddge.com']" --output text
```

If that returns nothing, don't promise a live mamtaj login tomorrow (see Q&A).

**Step 6. (Optional) Install missing tools** if you want to demo them locally:

```powershell
choco install jq -y
choco install tfsec -y
```

Otherwise demo the security scan from a GitHub Actions run instead.

**Step 7. Test the Slack webhook** if Demo 2 will show a notification:

```powershell
curl -s -X POST -H "Content-type: application/json" --data '{"text":"handover demo test"}' $env:SLACK_WEBHOOK_URL
```

---

## Part 2 — 30 minutes before the call

- [ ] `git status` clean; on `main`; `git pull` done.
- [ ] `pwsh -File scripts/preflight.ps1` run once, green output on screen.
- [ ] Tabs/windows open, in order:
  1. Editor on the repo (folders collapsed to top level)
  2. GitHub → Actions tab (a recent green PR run ready to point at)
  3. Incognito browser at `https://d-90663e376f.awsapps.com/start`
  4. Terminal at repo root, font size bumped up
  5. `docs/rollback.md` and `docs/access-matrix.md` open
- [ ] Notifications silenced, unrelated apps closed.
- [ ] `docs/handover-guide.md` Section 8 open as speaker notes.

---

## Part 3 — Run of show (90 min)

For each demo: **Open → Say → Do → Fallback.**

### 0:00–0:10 Intro & context
"Goal: hand over the AWS GitOps platform. Four things — how it's built, how a change ships,
how people log in, how we roll back. At the end I'll ask for sign-off."

### 0:10–0:25 Demo 1 — Architecture & repo walkthrough
- Open: repo tree → `infra/bootstrap/main.tf` → `envs/dev/main.tf` → `modules/vpc/main.tf`.
- Say: "`infra/` is one-time foundation, `modules/` are reusable blocks, `envs/` are
  dev/staging/prod using the same blocks with different inputs."
- Do: `terraform state list` (or show the S3 state bucket) as "Terraform's memory."
- Key point: "There's no hardcoded `us-west-2` anywhere — region is injected at deploy time
  via `var.aws_region`, `-backend-config`, and the GitHub `AWS_REGION` variable. That's why
  the region grep returns zero."
- Fallback: if `terraform state list` needs creds you lack live, show the state bucket in the
  console or the `terraform { backend "s3" {...} }` block.

### 0:25–0:40 Demo 2 — Full PR cycle
- Do: `git checkout -b demo/add-tag`, add a tag, push, `gh pr create`.
- Open: the PR's Actions checks — fmt, validate (dev/staging/prod matrix), plan comment.
- Say: "On merge, OIDC hands GitHub a 1-hour credential — no stored keys. Dev/staging
  auto-apply; prod stops at a manual gate."
- Fallback (safer): stop at the plan comment; point to a previously merged green run to show
  the apply + Slack step. If you merge, do it on a throwaway tag change to **dev only**.

### 0:40–0:50 Demo 3 — SSO login
- Do: incognito → portal URL → `@guddge.com` login → MFA → account `286684483345` → console.
- Say: "No IAM users, no keys — work email + MFA. Disable in Entra and access is gone instantly."
- Fallback: if SSO/MFA is flaky, play a clip recorded the night before.

### 0:50–1:00 Demo 4 — Rollback
- Open: `docs/rollback.md`. Walk **Phase 4 (OIDC, 15-min RTO)** — quickest to show.
- Say: "Every phase has a defined RTO. Phase 4 is 15 minutes; Phase 3 (region/data) is 2–4
  hours because it restores DB snapshots. Nothing here is irreversible."
- Do NOT run destructive rollback commands live — walk the doc.

### 1:00–1:10 Access matrix
- Open: `docs/access-matrix.md` + `infra/sso/terraform.tfvars`.
- Say: "Source of truth for who can do what — code-managed, reviewed, auditable. Adding a
  developer is a one-line change here, then PR."
- Caution: if you demo "add a user," use a name already synced (e.g. `bhanua`). Adding an
  unsynced user makes `terraform plan` fail with "user not found."

### 1:10–1:20 Q&A — see Part 5.
### 1:20–1:30 Sign-off — see Part 6.

---

## Part 4 — Repo-specific landmines

1. **`tfsec`/`checkov` not installed locally.** Security-scan job can't run on your laptop —
   demo it from GitHub Actions, or install one tool.
2. **`jq` not installed.** Anything in `deployment-runbook.md` / inventory / audit scripts that
   pipes to `jq` fails locally. (Smoke tests use `aws --query` + `awk`, so they're fine.)
3. **Smoke tests are bash and hit live AWS.** `tests/smoke_*.sh` use `#!/usr/bin/env bash` and
   call live `aws` APIs. Run in Git Bash/WSL, only against deployed infra with valid creds.
   Otherwise show a prior green run.
4. **`infra/sso/terraform.tfvars` is untracked** and lists only `sreevatsav` + `bhanua` — not
   `mamtaj`, even though the handover narrative centers on mamtaj.
5. **`mamtaj@guddge.com` may not be SCIM-synced yet** (per `admin-handover.md`). Admin cutover
   is blocked until Entra assignment + sync completes. Verify (Part 1, Step 5).
6. **Leftover principals you'll be asked about:** the auto-created "Amazon Q User" group on
   AdministratorAccess (not Terraform-managed) and the `n8n-user` IAM user (intentional
   break-glass). Have the cleanup answer ready.
7. **`terraform fmt -diff` errors on Windows** ("diff not found"). Use `terraform fmt -check`
   (no `-diff`).
8. **Terraform version:** local 1.10.5, pipeline pins 1.8.5. Harmless locally; if you run
   `terraform version` on screen, say "CI pins 1.8.5 for reproducibility."

---

## Part 5 — Likely questions and crisp answers

- **"If you deploy to us-west-2, why zero `us-west-2` references?"** — Region is parameterized
  (`var.aws_region`) and injected at runtime via `-backend-config` and the GitHub `AWS_REGION`
  variable. Re-targeting is a variable change.
- **"How do we know there are no secrets in the repo?"** — CI runs secret scanning, and
  `grep -rE 'AKIA[A-Z0-9]{16}' .` from the repo root returns nothing. Auth is OIDC-only
  (16/16 workflow steps use `role-to-assume`). *(Run that grep from the repo root, not `~/.kiro`.)*
- **"What stops a bad change reaching prod?"** — Branch protection + CODEOWNERS + required
  checks (fmt/validate/plan/security), a destructive-change gate, and a manual `production`
  environment approval before apply.
- **"Who can grant admin?"** — It's code in `infra/sso/terraform.tfvars`, changed only via
  reviewed PR; every change is in git history and CloudTrail.
- **"What about the Amazon Q admin group / n8n-user?"** — Q group is auto-created, not
  TF-managed, slated for IAM-cleanup review; `n8n-user` is deliberate break-glass, removed last
  after SSO admin is proven.
- **"Can mamtaj log in now?"** — If not yet synced: "Entra assignment + SCIM sync is the one
  open precondition; once the user appears in the Identity Store it's a one-line tfvars add +
  apply. Break-glass access covers us meanwhile."

---

## Part 6 — Sign-off checklist (end of call)

- [ ] New admin can log in via SSO (or: open item + target date if mamtaj not synced)
- [ ] New admin has AdministratorAccess
- [ ] OIDC working (point at a green Actions run)
- [ ] Slack notifications arriving
- [ ] `docs/rollback.md` reviewed and understood
- [ ] Old bootstrap role decommission timeline agreed
- [ ] SCIM token rotation cadence agreed (recommend 90 days)
- [ ] `n8n-user` break-glass removal is the final step, after repeated SSO admin success

---

## Security heads-up (do regardless of the demo)

A real AWS access key and its secret were pasted into a previous Kiro chat session and are
stored in local session logs under `~/.kiro/sessions/...`. The repo itself is clean. Two actions:

1. **Rotate/delete those credentials in IAM** if not already done — treat them as compromised.
2. **During the demo, run the `AKIA` security check from the repo root**
   (`aws-gitops-migration\`), not from `~/.kiro`, or the grep will surface that logged key.
