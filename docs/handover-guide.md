# Complete Handover Guide: AWS GitOps Migration

> This document explains every major deliverable in plain English, as if you've never seen any of this before. It includes diagrams, walkthroughs, and demos for each piece.

---

## Table of Contents

1. [Architecture Diagram — What Does This System Look Like?](#1-architecture-diagram)
2. [Repo Structure — Where Does Everything Live?](#2-repo-structure)
3. [Terraform Code — What Is It and How Does It Work?](#3-terraform-code)
4. [Identity Center + Entra Setup — How Do People Log In?](#4-identity-center--entra-setup)
5. [GitHub Actions Workflow — How Does Code Get Deployed?](#5-github-actions-workflow)
6. [Rollback Plan — What If Something Goes Wrong?](#6-rollback-plan)
7. [Access Matrix — Who Can Do What?](#7-access-matrix)
8. [Final Handover Call — Demo Script](#8-final-handover-call-demo)

---

## 1. Architecture Diagram

### What's Happening at a High Level

Think of this system like a factory assembly line:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          YOUR COMPUTER / BROWSER                          │
│                                                                          │
│  Developer writes code ──> Pushes to GitHub ──> Opens a Pull Request     │
└────────────────────────────────────┬─────────────────────────────────────┘
                                     │
                                     ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                              GITHUB                                       │
│                                                                          │
│  Pull Request triggers AUTOMATED CHECKS:                                 │
│    ✓ Is the code formatted correctly?                                    │
│    ✓ Is the code valid (no typos)?                                       │
│    ✓ What will change in AWS? (plan preview)                             │
│    ✓ Any security issues?                                                │
│                                                                          │
│  If all checks pass AND someone approves ──> Merge to main branch        │
│  After merge ──> DEPLOY automatically (dev/staging) or with approval     │
│                  (prod)                                                   │
└────────────────────────────────────┬─────────────────────────────────────┘
                                     │
                                     │ OIDC (temporary credentials, no
                                     │ permanent passwords stored anywhere)
                                     ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                           AWS (us-west-2, Oregon)                         │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │  STATE BACKEND (the "memory" of what exists)                        │ │
│  │    S3 Bucket ──> stores what Terraform knows about your infra       │ │
│  │    DynamoDB  ──> prevents two people from changing things at once   │ │
│  │    KMS Key   ──> encrypts everything at rest                        │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                   │
│  │  DEV account │  │STAGING acct  │  │ PROD account │                   │
│  │  (playground)│  │(pre-prod)    │  │(real users)  │                   │
│  │  Auto-deploy │  │Auto-deploy   │  │Manual gate   │                   │
│  └──────────────┘  └──────────────┘  └──────────────┘                   │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │  IAM IDENTITY CENTER (the "front door" for humans)                  │ │
│  │    ← connected to Microsoft Entra ID (your company's login system)  │ │
│  │    ← users log in with their work email + MFA                       │ │
│  │    ← get assigned to groups that control what they can do           │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  Security layer:                                                         │
│    CloudTrail ──> records every API call (audit log)                     │
│    GuardDuty  ──> watches for suspicious activity                        │
└──────────────────────────────────────────────────────────────────────────┘
```

### In Even Simpler Terms

- **GitHub** = where the code lives and where changes are reviewed
- **Terraform** = the tool that reads code files and creates/updates AWS resources automatically
- **OIDC** = a way for GitHub to prove its identity to AWS without storing passwords
- **IAM Identity Center** = the single login portal where employees access AWS
- **Entra ID** = Microsoft's identity system (your company directory) — it tells AWS who your employees are

---

## 2. Repo Structure

### Why Is It Organized This Way?

Think of it like a house:
- `infra/` = the foundation and plumbing (things you set up once)
- `modules/` = reusable building blocks (like pre-fabricated wall sections)
- `envs/` = the actual rooms (dev, staging, prod — each uses the same building blocks differently)
- `.github/` = the construction manager's rulebook (automation)
- `docs/` = the instruction manuals
- `scripts/` = the power tools

### Directory Map

```
aws-gitops-migration/
│
├── infra/                          ← ONE-TIME SETUP STUFF
│   ├── bootstrap/                  ← Creates the S3 bucket, DynamoDB table, KMS key, OIDC provider
│   │   ├── main.tf                    (the actual resources)
│   │   ├── variables.tf               (configurable inputs)
│   │   └── outputs.tf                 (values other parts of the system need)
│   ├── deploy-roles/               ← IAM roles GitHub uses to deploy (one per environment)
│   └── sso/                        ← Identity Center config (who can log in and what they can do)
│
├── modules/                        ← REUSABLE LEGO BLOCKS
│   ├── vpc/                        ← Network setup (subnets, routing)
│   ├── s3/                         ← S3 bucket template (encryption, versioning baked in)
│   ├── kms/                        ← Encryption key template
│   ├── iam/                        ← Permission/role template
│   ├── cloudtrail/                 ← Audit logging
│   ├── guardduty/                  ← Threat detection
│   └── sso/                        ← SSO permission sets and group assignments
│
├── envs/                           ← ACTUAL ENVIRONMENTS (each "room" in the house)
│   ├── dev/                        ← Development (safe to experiment)
│   │   ├── main.tf                    (calls modules with dev-specific settings)
│   │   ├── variables.tf               (dev-specific inputs)
│   │   └── terraform.tfvars           (dev-specific values)
│   ├── staging/                    ← Pre-production (mirrors prod closely)
│   └── prod/                       ← Production (real users, extra protections)
│
├── .github/
│   ├── workflows/
│   │   ├── pr-plan.yml             ← Runs on every PR (fmt/validate/plan/scan)
│   │   ├── apply-dev.yml           ← Auto-deploys to dev after merge
│   │   ├── apply-staging.yml       ← Auto-deploys to staging after merge
│   │   └── apply-prod.yml          ← Deploys to prod ONLY with manual approval
│   ├── CODEOWNERS                  ← Who must approve changes to what
│   └── branch-protection.md       ← Rules for the main branch
│
├── docs/                           ← DOCUMENTATION
│   ├── access-matrix.md           ← Who can access what
│   ├── rollback.md                ← What to do if things go wrong
│   ├── migration-checklist.md     ← Status of every resource being migrated
│   ├── sso-setup.md              ← How Entra ID SSO was configured
│   ├── oidc-setup.md             ← How GitHub OIDC was configured
│   └── runbook.md                ← Day-to-day operational procedures
│
├── scripts/                        ← HELPER SCRIPTS
│   ├── bootstrap.md               ← Step-by-step manual bootstrap (one-time)
│   ├── inventory_export.sh        ← Exports current AWS resources to JSON
│   └── state_migration.sh        ← Imports existing resources into Terraform
│
└── tests/                          ← VERIFICATION SCRIPTS
    ├── smoke_dev.sh               ← Quick health check for dev
    ├── smoke_staging.sh           ← Quick health check for staging
    └── smoke_prod.sh             ← Quick health check for prod
```

### Key Concept: Why "Modules" and "Envs" Are Separate

Imagine you're building 3 houses (dev, staging, prod). Instead of designing each house from scratch, you create a blueprint for "a room" (a module). Then each house uses that same blueprint but can customize the size, paint color, etc.

- `modules/vpc/` defines HOW to build a network, but not WHICH network
- `envs/dev/main.tf` says "Build me a network using the VPC module with THESE specific settings"
- `envs/prod/main.tf` says "Build me a network using the SAME VPC module but with THESE different settings"

This means: fix a bug in the module once → every environment gets the fix.

---

## 3. Terraform Code

### What Is Terraform?

Terraform is a tool that lets you describe your infrastructure (servers, databases, networks, security rules) in text files. You write what you WANT to exist, and Terraform figures out how to make it happen.

### The Core Files in Every Terraform Directory

| File | Purpose | Analogy |
|------|---------|---------|
| `main.tf` | The actual resources to create | The recipe |
| `variables.tf` | Inputs you can customize | The ingredient list |
| `outputs.tf` | Values this module shares with others | The finished dish |
| `terraform.tfvars` | The actual values for this specific use | The grocery shopping list |

### Demo: Reading the Bootstrap Module

Here's a simplified walkthrough of `infra/bootstrap/main.tf`:

```hcl
# STEP 1: Tell Terraform which cloud provider to use
provider "aws" {
  region = var.aws_region    # "us-west-2" — Oregon
}

# STEP 2: Create an encryption key (KMS)
# Think of this as a master lock that protects all your data
resource "aws_kms_key" "state" {
  description         = "Encrypts the Terraform state file"
  enable_key_rotation = true   # Automatically changes the lock every year
}

# STEP 3: Create an S3 bucket (the "filing cabinet" for Terraform's memory)
resource "aws_s3_bucket" "state" {
  bucket = "mycompany-terraform-state-123456"

  lifecycle {
    prevent_destroy = true   # SAFETY: prevents accidental deletion
  }
}

# STEP 4: Create a DynamoDB table (the "reservation system")
# Prevents two people from making changes simultaneously
resource "aws_dynamodb_table" "lock" {
  name     = "terraform-state-lock"
  hash_key = "LockID"
}

# STEP 5: Register GitHub as a trusted identity provider (OIDC)
# This tells AWS: "GitHub Actions is allowed to prove who it is"
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
```

### How to Run Terraform (the actual commands)

```bash
# Step 1: Go to the directory
cd infra/bootstrap/

# Step 2: Initialize (downloads the AWS plugin)
terraform init

# Step 3: Plan (shows what WILL happen — doesn't change anything yet)
terraform plan
# Output: "I will create 1 KMS key, 1 S3 bucket, 1 DynamoDB table, 1 OIDC provider"

# Step 4: Apply (actually creates the resources)
terraform apply
# You type "yes" to confirm

# Step 5: Check what exists
terraform state list
# Shows all resources Terraform is managing
```

### The "State" Concept (Critical to Understand)

Terraform keeps a "state file" — think of it as a spreadsheet that says:
- "S3 bucket `mycompany-terraform-state` exists, it was created at 2pm, it has encryption turned on"

Without this file, Terraform doesn't know what it already created. That's why we store it in S3 (safe, versioned, encrypted) instead of on someone's laptop.

---

## 4. Identity Center + Entra Setup

### The Problem This Solves

Before this setup:
- People shared AWS access keys (passwords) over Slack
- No one knew who had access to what
- If someone left the company, you had to hunt down all their keys

After this setup:
- People log in with their work email (the same one they use for Outlook/Teams)
- MFA (multi-factor authentication) is required
- When someone leaves, disable them in Entra → they instantly lose AWS access

### How It Works (The Flow)

```
┌─────────────────┐         ┌───────────────────┐         ┌──────────────────┐
│  EMPLOYEE        │         │  MICROSOFT ENTRA   │         │  AWS IDENTITY    │
│                 │         │  (Company Directory)│         │  CENTER          │
│  Opens browser  │────────>│                    │────────>│                  │
│  Goes to AWS    │         │  "Is this person   │  SAML   │  "OK, they're    │
│  login portal   │         │   real? Check      │  token  │   verified.      │
│                 │<────────│   their password   │<────────│   Show them      │
│  Sees their     │         │   + MFA"           │         │   their allowed  │
│  allowed        │         │                    │         │   accounts"      │
│  accounts       │         │  YES ✓             │         │                  │
└─────────────────┘         └───────────────────┘         └──────────────────┘
```

### Step-by-Step Setup (Already Done — Here's What Happened)

**Part A: Connect Entra to AWS (SAML — the "trust handshake")**

1. In Microsoft Entra admin center → created an "Enterprise Application" for AWS
2. Configured SAML (Security Assertion Markup Language) — this is the protocol that lets Entra prove someone's identity to AWS
3. Uploaded certificates between the two systems (like exchanging ID cards so they trust each other)

**Part B: Automatic User Syncing (SCIM)**

SCIM = System for Cross-domain Identity Management. In plain English: when you add someone to Entra, they automatically appear in AWS.

- Entra pushes user info (name, email) to AWS Identity Center
- In this specific setup: users sync automatically, but groups are managed in AWS (via Terraform)

**Part C: Group-to-Permission Mapping (Terraform manages this)**

The Terraform code in `infra/sso/` creates groups and assigns permissions:

```hcl
# Creates the "aws-admins" group in AWS
# Adds specific users to it
# Assigns the "AdministratorAccess" permission set to that group
managed_groups = {
  "aws-admins"     = ["mamtaj@guddge.com", "bhanua@guddge.com"]
  "aws-developers" = ["bhanua@guddge.com"]
}
```

**Part D: MFA + Conditional Access (Entra enforces this)**

- A Conditional Access policy in Entra says: "Anyone accessing the AWS app MUST use MFA"
- This means: even if someone steals a password, they can't get in without the phone/authenticator

### Demo: A User Logging In

1. User goes to `https://d-90663e376f.awsapps.com/start`
2. Gets redirected to Microsoft login page
3. Enters their `@guddge.com` email and password
4. Gets prompted for MFA (authenticator app or SMS)
5. After MFA succeeds → sees a list of AWS accounts they have access to
6. Clicks "Management Console" next to their permission set
7. They're now logged into AWS with the exact permissions their group allows

---

## 5. GitHub Actions Workflow

### What Are GitHub Actions?

GitHub Actions is an automation system built into GitHub. You write a YAML file that says "when X happens, do Y." It's like setting up dominoes — one event triggers a chain of automated steps.

### The Two Main Workflows

**Workflow 1: PR Checks (runs when you open a Pull Request)**

```
Developer opens a Pull Request
        │
        ▼
┌───────────────────────────────────────────────────┐
│  JOB 1: FORMAT CHECK                              │
│  "Is the code formatted consistently?"            │
│  Command: terraform fmt -check                    │
│  Result: ✓ Pass or ✗ Fail                         │
├───────────────────────────────────────────────────┤
│  JOB 2: VALIDATE (runs for dev, staging, prod)    │
│  "Is the code syntactically correct?"             │
│  Command: terraform validate                      │
│  Result: ✓ Pass or ✗ Fail                         │
├───────────────────────────────────────────────────┤
│  JOB 3: SECURITY SCAN                             │
│  "Are there any security best-practice issues?"   │
│  Tool: tfsec or checkov                           │
│  Result: ✓ Pass or ✗ Fail on HIGH/CRITICAL        │
├───────────────────────────────────────────────────┤
│  JOB 4: PLAN                                      │
│  "What will actually change in AWS?"              │
│  Command: terraform plan                          │
│  Posts the plan as a PR comment so reviewers see   │
│  exactly what will happen                         │
├───────────────────────────────────────────────────┤
│  JOB 5: DESTRUCTIVE CHECK                         │
│  "Will this delete anything?"                     │
│  If yes → FAILS unless the PR has a special label │
└───────────────────────────────────────────────────┘
```

**Workflow 2: Apply (runs after merge to main)**

```
PR merged to main
        │
        ▼
┌───────────────────────────────────────────────────┐
│  DEV: Automatically applies changes               │
│  (no human approval needed)                       │
├───────────────────────────────────────────────────┤
│  STAGING: Automatically applies changes           │
│  (no human approval needed)                       │
├───────────────────────────────────────────────────┤
│  PROD: WAITS for manual approval                  │
│  (Platform Owner must click "Approve" in GitHub)  │
│  Then applies changes                             │
│  Then runs smoke tests                            │
│  Then notifies Slack                              │
└───────────────────────────────────────────────────┘
```

### Demo: The Actual Workflow File (Simplified)

Here's what `.github/workflows/pr-plan.yml` says in plain English:

```yaml
name: Terraform PR Checks

# WHEN: someone opens or updates a Pull Request that touches infrastructure files
on:
  pull_request:
    branches: [main]
    paths: ['infra/**', 'modules/**', 'envs/**']

# PERMISSIONS: this workflow can request temporary AWS credentials via OIDC
permissions:
  id-token: write       # Needed for OIDC
  contents: read        # Can read the code
  pull-requests: write  # Can post comments on the PR

jobs:
  # Job 1: Check formatting
  fmt:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4          # Download the code
      - uses: hashicorp/setup-terraform@v3 # Install Terraform
      - run: terraform fmt -check -recursive ./infra ./modules ./envs

  # Job 2: Validate each environment
  validate:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        env: [dev, staging, prod]  # Run this job 3 times (once per env)
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - run: terraform init -backend=false    # Initialize without connecting to S3
        working-directory: envs/${{ matrix.env }}
      - run: terraform validate
        working-directory: envs/${{ matrix.env }}
```

### The OIDC Authentication (No Passwords!)

Traditional (bad) approach:
```
Store AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY as GitHub secrets
→ These never expire
→ If leaked, attacker has permanent access
```

Our approach (OIDC):
```
GitHub says to AWS: "I am the repo guddge/aws-gitops-migration, running on branch main"
AWS says: "I trust that identity. Here's a temporary credential that expires in 1 hour."
→ No permanent credentials stored anywhere
→ If intercepted, expires automatically
→ Scoped to only what that environment needs
```

---

## 6. Rollback Plan

### What Is a Rollback?

A rollback means "undo what we just did and go back to how things were before." Like the undo button, but for infrastructure.

### Why Do We Need One?

Because things can go wrong during a migration:
- A resource might be misconfigured
- A database might not copy correctly
- An authentication change might lock everyone out

### The Four Rollback Phases

Each phase corresponds to a stage of the migration:

```
┌─────────────────────────────────────────────────────────────────────┐
│  PHASE 1: BOOTSTRAP ROLLBACK                                        │
│  Recovery Time: ~30 minutes                                         │
│                                                                     │
│  What went wrong: The S3 bucket, DynamoDB table, or OIDC provider   │
│  was created incorrectly.                                           │
│                                                                     │
│  What we do: Delete the misconfigured resources and try again.      │
│  Safety: These are empty/new resources, so no data loss.            │
├─────────────────────────────────────────────────────────────────────┤
│  PHASE 2: STATE IMPORT ROLLBACK                                     │
│  Recovery Time: ~1 hour                                             │
│                                                                     │
│  What went wrong: We told Terraform about an existing resource,     │
│  but something was wrong (wrong resource ID, wrong configuration).  │
│                                                                     │
│  What we do: Remove the resource from Terraform's "memory"          │
│  (the state file). The actual AWS resource is NOT deleted.          │
│  Think of it as: erasing a line from the spreadsheet, not           │
│  demolishing the building.                                          │
├─────────────────────────────────────────────────────────────────────┤
│  PHASE 3: REGION MIGRATION ROLLBACK                                 │
│  Recovery Time: 2-4 hours (depends on data size)                    │
│                                                                     │
│  What went wrong: Resources in us-west-2 aren't working right,      │
│  or data didn't copy correctly.                                     │
│                                                                     │
│  What we do:                                                        │
│  - For databases: restore from the pre-migration snapshot           │
│  - For networks: revert the region variable and re-apply            │
│  - For DNS: point records back to the old region                    │
│                                                                     │
│  This is the biggest rollback because it involves data.             │
├─────────────────────────────────────────────────────────────────────┤
│  PHASE 4: OIDC CUTOVER ROLLBACK                                     │
│  Recovery Time: ~15 minutes                                         │
│                                                                     │
│  What went wrong: GitHub Actions can't log in to AWS anymore        │
│  (OIDC is broken).                                                  │
│                                                                     │
│  What we do: Temporarily re-enable the old bootstrap IAM role       │
│  with static credentials. Fix the OIDC config. Then switch back.    │
└─────────────────────────────────────────────────────────────────────┘
```

### Demo: How to Execute Phase 2 Rollback

Scenario: You imported a VPC into Terraform but used the wrong VPC ID.

```bash
# Step 1: See what Terraform thinks will happen
terraform plan
# Output: "aws_vpc.this will be DESTROYED" ← BAD! We don't want to delete the VPC!

# Step 2: Remove it from Terraform's knowledge (does NOT delete the VPC in AWS)
terraform state rm module.vpc.aws_vpc.this
# Output: "Removed module.vpc.aws_vpc.this from state"

# Step 3: Verify — now Terraform doesn't know about it
terraform plan
# Output: no changes (the VPC still exists in AWS, Terraform just doesn't manage it)

# Step 4: Re-import with the CORRECT ID
terraform import module.vpc.aws_vpc.this vpc-CORRECT_ID
```

---

## 7. Access Matrix

### What Is an Access Matrix?

It's a table that answers: "Who can do what, where?"

Think of it like a hotel key card system:
- Each person has a key card (their identity)
- Each floor has different access levels (AWS accounts)
- Each card is programmed for specific floors (permission sets)

### The Access Matrix for This Project

| Group | What They Can Do | Who's In It | Session Length |
|-------|-----------------|-------------|---------------|
| **aws-admins** | EVERYTHING (full admin) | mamtaj, bhanua, sreevatsav (temp) | 2 hours |
| **aws-powerusers** | Almost everything except creating IAM users/policies | brucew | 8 hours |
| **aws-developers** | Build apps (EC2, Lambda, S3, databases) but can't change security settings | bhanua | 8 hours |
| **aws-readonly** | Can look but can't touch | kartikav | 8 hours |
| **aws-billing** | Can only see costs and billing info | maheshg | 8 hours |

### Machine Access (No Humans Involved)

| Role | What Triggers It | What It Can Do |
|------|-----------------|----------------|
| `github-deploy-dev` | Any PR or merge to main | Manage dev resources only |
| `github-deploy-staging` | Merge to main only | Manage staging resources only |
| `github-deploy-prod` | Merge to main + manual approval + environment gate | Manage prod resources only |

### How to Change Access

**Add a new person to aws-developers:**

1. Make sure they exist in Entra ID (they have a @guddge.com email)
2. Wait for SCIM to sync them to AWS (usually minutes)
3. Edit `infra/sso/terraform.tfvars`:
   ```hcl
   managed_groups = {
     "aws-developers" = ["bhanua@guddge.com", "newperson@guddge.com"]  # ← add here
   }
   ```
4. Open a PR → get it reviewed → merge → Terraform applies the change
5. New person can now log in via the SSO portal

**Remove someone (they left the company):**

1. Disable them in Entra ID (HR usually does this)
2. SCIM sync removes them from AWS Identity Center
3. They can no longer log in — immediate effect
4. Clean up: remove them from `terraform.tfvars` and merge (housekeeping)

---

## 8. Final Handover Call Demo

### Agenda (60-90 minutes)

```
0:00 - 0:10  │  Introduction & Context
0:10 - 0:25  │  Demo 1: Architecture & Repo Walkthrough
0:25 - 0:40  │  Demo 2: Making a Change (Full PR → Deploy Cycle)
0:40 - 0:50  │  Demo 3: SSO Login Experience
0:50 - 1:00  │  Demo 4: Rollback Procedure
1:00 - 1:10  │  Access Matrix Review & Transfer
1:10 - 1:20  │  Q&A
1:20 - 1:30  │  Sign-off & Next Steps
```

---

### Demo 1: Architecture & Repo Walkthrough (15 min)

**What to show:**

1. Open the GitHub repo and walk through the folder structure
2. Open `infra/bootstrap/main.tf` — explain each resource (S3, DynamoDB, KMS, OIDC)
3. Open `envs/dev/main.tf` — show how it calls modules
4. Open `modules/vpc/main.tf` — show the reusable pattern
5. Show the state in S3: "This is Terraform's memory of what exists"

**Script:**
> "Here's our repo. Everything in `infra/` is foundational — you set it up once. Everything in `modules/` is reusable. Everything in `envs/` is environment-specific. Let me show you how dev calls the VPC module..."

---

### Demo 2: Making a Change — Full PR Cycle (15 min)

**What to show:**

1. Create a branch: `git checkout -b demo/add-tag`
2. Make a small change (add a tag to a resource)
3. Push and open a PR
4. Watch the automated checks run:
   - Format check ✓
   - Validate ✓
   - Plan output posted as PR comment
5. Show the plan comment: "This is what will change"
6. Approve and merge
7. Show the apply workflow triggering for dev
8. Show the Slack notification

**Script:**
> "Watch what happens when I merge. GitHub Actions picks it up, assumes the deploy role via OIDC (no passwords stored!), runs `terraform apply`, and notifies Slack. For prod, it would stop here and wait for someone to click Approve."

---

### Demo 3: SSO Login Experience (10 min)

**What to show:**

1. Open an incognito browser
2. Go to `https://d-90663e376f.awsapps.com/start`
3. Log in with a test user's @guddge.com email
4. Show the MFA prompt
5. After login: show the list of available accounts and permission sets
6. Click into the console — show that they have the expected level of access
7. Try to do something outside their permission (it should fail)

**Script:**
> "Notice: no AWS access keys, no IAM user passwords. Just their normal work email with MFA. If we disable them in Entra tomorrow, they lose access instantly."

---

### Demo 4: Rollback Procedure (10 min)

**What to show:**

1. Open `docs/rollback.md`
2. Walk through Phase 4 (OIDC rollback) since it's the quickest to demonstrate:
   - "If GitHub can't authenticate to AWS..."
   - Show the diagnostic commands
   - Show how to temporarily fall back to static credentials
   - Explain that this is a 15-minute recovery
3. Mention Phase 3 (region rollback) for stateful resources: "If we needed to go back to eu-west-2, here are the exact commands for each database type"

**Script:**
> "Every rollback has a defined recovery time. Phase 4 is 15 minutes. Phase 3 is 2-4 hours because it involves restoring database snapshots. The key point: nothing is irreversible. We took snapshots before every major step."

---

### Demo 5: Access Matrix Review (10 min)

**What to show:**

1. Open `docs/access-matrix.md`
2. Walk through each group and who's in it
3. Show the Terraform code that enforces this (`infra/sso/terraform.tfvars`)
4. Demonstrate: "If I want to add a new developer, I change ONE line here, open a PR, and merge"
5. Confirm: "Are these assignments correct? Anyone need to be added or removed?"

**Script:**
> "This is your source of truth for who can do what. It's code-managed, so every change is reviewed, approved, and auditable. No more 'who gave that person admin access?'"

---

### Sign-off Checklist

Before ending the call, confirm:

- [ ] New admin (mamtaj@guddge.com) can log in via SSO
- [ ] New admin has AdministratorAccess permission set
- [ ] New admin can run `terraform plan` locally (or via PR)
- [ ] GitHub Actions OIDC is working (show a recent successful workflow run)
- [ ] Slack notifications are arriving
- [ ] `docs/rollback.md` has been reviewed and understood
- [ ] Emergency contacts are documented
- [ ] Old bootstrap IAM role will be decommissioned (agree on timeline)
- [ ] SCIM token rotation schedule is agreed (recommend every 90 days)

---

## Quick Reference: Day-to-Day Operations

| I want to... | Do this... |
|--------------|-----------|
| Add a new AWS resource | Add Terraform code in the right env → open PR → merge |
| Give someone AWS access | Add them to a group in `infra/sso/terraform.tfvars` → PR → merge |
| Remove someone's access | Disable in Entra (immediate) + clean up tfvars (housekeeping) |
| See what Terraform manages | `terraform state list` in any env directory |
| See what will change | `terraform plan` (or just open a PR — it posts the plan) |
| Roll back a bad change | Follow `docs/rollback.md` for the relevant phase |
| Rotate the SCIM token | Regenerate in AWS Identity Center → update in Entra → test sync |
| Check security posture | Look at GuardDuty findings + CloudTrail logs |
| See who did what | CloudTrail event history (every API call is logged) |

---

## Glossary

| Term | Plain English |
|------|--------------|
| **Terraform** | Tool that creates AWS resources from code files |
| **State file** | Terraform's memory of what it created |
| **Module** | A reusable template for a group of resources |
| **Provider** | Plugin that connects Terraform to AWS |
| **OIDC** | Protocol for proving identity without passwords |
| **SAML** | Protocol for single sign-on (how Entra talks to AWS) |
| **SCIM** | Protocol for automatically syncing user accounts |
| **KMS** | AWS Key Management Service — encryption keys |
| **IAM** | Identity and Access Management — permissions |
| **SSO** | Single Sign-On — one login for everything |
| **MFA** | Multi-Factor Authentication — password + phone |
| **PR** | Pull Request — a proposed code change for review |
| **CI/CD** | Continuous Integration / Continuous Deployment — automation |
| **GuardDuty** | AWS service that detects suspicious activity |
| **CloudTrail** | AWS service that logs every API call |
