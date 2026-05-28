# Deployment Runbook - AWS GitOps Migration

> **Purpose**: Step-by-step guide to deploy the AWS GitOps infrastructure from scratch.
> Copy-paste ready commands are provided for each phase.

---

## Prerequisites

| Tool | Minimum Version | Install |
|------|----------------|---------|
| AWS CLI | 2.x | `brew install awscli` / `choco install awscli2` |
| Terraform | >= 1.5 | `brew install terraform` / `choco install terraform` |
| GitHub CLI | >= 2.30 | `brew install gh` / `choco install gh` |
| Git | >= 2.40 | `brew install git` / `choco install git` |
| jq | >= 1.6 | `brew install jq` / `choco install jq` |

Ensure you are authenticated:

```bash
aws sts get-caller-identity
gh auth status
```

---

## Phase 1: Create GitHub Repository

```bash
# Set variables
export GH_ORG="your-org"
export GH_REPO="aws-infrastructure"

# Create private repository
gh repo create "${GH_ORG}/${GH_REPO}" \
  --private \
  --description "AWS infrastructure managed via Terraform + GitOps" \
  --clone

cd "${GH_REPO}"

# Initialize with main branch
git checkout -b main
cp -r /path/to/aws-gitops-migration/* .
git add -A
git commit -m "feat: initial infrastructure scaffolding"
git push -u origin main
```

---

## Phase 2: Bootstrap AWS

### 2.1 Create Temporary IAM Role for Bootstrap

```bash
# Create a temporary admin role for bootstrapping
# This role will be decommissioned in Phase 9
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION="us-west-2"

cat > /tmp/bootstrap-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT_ID:root"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

sed -i "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/" /tmp/bootstrap-trust-policy.json

aws iam create-role \
  --role-name gitops-bootstrap-temp \
  --assume-role-policy-document file:///tmp/bootstrap-trust-policy.json \
  --tags Key=Purpose,Value=bootstrap Key=Temporary,Value=true

aws iam attach-role-policy \
  --role-name gitops-bootstrap-temp \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

### 2.2 Assume Bootstrap Role

```bash
CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/gitops-bootstrap-temp" \
  --role-session-name "bootstrap-session" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.Credentials.SessionToken')

# Verify
aws sts get-caller-identity
```

### 2.3 Run Terraform Apply on Bootstrap Module

```bash
cd infra/bootstrap/

terraform init

terraform plan -out=bootstrap.tfplan \
  -var="account_id=${AWS_ACCOUNT_ID}" \
  -var="region=${AWS_REGION}" \
  -var="github_org=${GH_ORG}" \
  -var="github_repo=${GH_REPO}"

# Review the plan carefully, then apply
terraform apply bootstrap.tfplan
```

### 2.4 Migrate State to S3 Backend (Self-Referencing)

```bash
# Read outputs
export TF_STATE_BUCKET=$(terraform output -raw state_bucket_name)
export TF_STATE_KMS_KEY_ARN=$(terraform output -raw kms_key_arn)
export TF_STATE_KMS_KEY_ID=$(terraform output -raw kms_key_id)
export TF_STATE_LOCK_TABLE=$(terraform output -raw dynamodb_table_name)

# Add backend configuration
cat > backend.tf << EOF
terraform {
  backend "s3" {
    bucket         = "${TF_STATE_BUCKET}"
    key            = "bootstrap/terraform.tfstate"
    region         = "${AWS_REGION}"
    encrypt        = true
    kms_key_id     = "${TF_STATE_KMS_KEY_ID}"
    dynamodb_table = "${TF_STATE_LOCK_TABLE}"
  }
}
EOF

# Migrate local state to S3
terraform init -migrate-state -force-copy

# Verify state is in S3
terraform state list
```

---

## Phase 3: Configure GitHub Secrets

```bash
# Retrieve deploy role ARNs from bootstrap outputs
export AWS_DEPLOY_ROLE_DEV=$(terraform output -raw deploy_role_arn_dev)
export AWS_DEPLOY_ROLE_STAGING=$(terraform output -raw deploy_role_arn_staging)
export AWS_DEPLOY_ROLE_PROD=$(terraform output -raw deploy_role_arn_prod)

# Set repository secrets
gh secret set TF_STATE_BUCKET --body "${TF_STATE_BUCKET}" --repo "${GH_ORG}/${GH_REPO}"
gh secret set TF_STATE_KMS_KEY_ARN --body "${TF_STATE_KMS_KEY_ARN}" --repo "${GH_ORG}/${GH_REPO}"
gh secret set TF_STATE_KMS_KEY_ID --body "${TF_STATE_KMS_KEY_ID}" --repo "${GH_ORG}/${GH_REPO}"
gh secret set TF_STATE_LOCK_TABLE --body "${TF_STATE_LOCK_TABLE}" --repo "${GH_ORG}/${GH_REPO}"
gh secret set AWS_DEPLOY_ROLE_DEV --body "${AWS_DEPLOY_ROLE_DEV}" --repo "${GH_ORG}/${GH_REPO}"
gh secret set AWS_DEPLOY_ROLE_STAGING --body "${AWS_DEPLOY_ROLE_STAGING}" --repo "${GH_ORG}/${GH_REPO}"
gh secret set AWS_DEPLOY_ROLE_PROD --body "${AWS_DEPLOY_ROLE_PROD}" --repo "${GH_ORG}/${GH_REPO}"

# Slack webhook (obtain from your Slack app configuration)
gh secret set SLACK_WEBHOOK_URL --body "https://hooks.slack.com/services/YOUR/WEBHOOK/URL" --repo "${GH_ORG}/${GH_REPO}"
```

### Verify Secrets

```bash
gh secret list --repo "${GH_ORG}/${GH_REPO}"
```

Expected output:

```
TF_STATE_BUCKET         Updated 2024-XX-XX
TF_STATE_KMS_KEY_ARN    Updated 2024-XX-XX
TF_STATE_KMS_KEY_ID     Updated 2024-XX-XX
TF_STATE_LOCK_TABLE     Updated 2024-XX-XX
AWS_DEPLOY_ROLE_DEV     Updated 2024-XX-XX
AWS_DEPLOY_ROLE_STAGING Updated 2024-XX-XX
AWS_DEPLOY_ROLE_PROD    Updated 2024-XX-XX
SLACK_WEBHOOK_URL       Updated 2024-XX-XX
```

---

## Phase 4: Configure Branch Protection

```bash
# Protect main branch
gh api repos/${GH_ORG}/${GH_REPO}/branches/main/protection \
  --method PUT \
  --input - << 'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "terraform-plan",
      "terraform-validate",
      "tfsec",
      "checkov"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "require_last_push_approval": true
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
EOF

echo "Branch protection configured for main"
```

### Verify Branch Protection

```bash
gh api repos/${GH_ORG}/${GH_REPO}/branches/main/protection --jq '.required_status_checks.contexts[]'
```

---

## Phase 5: Create GitHub Environments

### 5.1 Create Dev Environment

```bash
gh api repos/${GH_ORG}/${GH_REPO}/environments/dev \
  --method PUT \
  --input - << 'EOF'
{
  "deployment_branch_policy": {
    "protected_branches": false,
    "custom_branch_policies": true
  }
}
EOF

# Allow deployments from any branch (for dev)
gh api repos/${GH_ORG}/${GH_REPO}/environments/dev/deployment-branch-policies \
  --method POST \
  --field name="*"
```

### 5.2 Create Staging Environment

```bash
gh api repos/${GH_ORG}/${GH_REPO}/environments/staging \
  --method PUT \
  --input - << 'EOF'
{
  "deployment_branch_policy": {
    "protected_branches": true,
    "custom_branch_policies": false
  }
}
EOF
```

### 5.3 Create Production Environment (with Reviewers)

```bash
# Get your GitHub user ID (or team ID for team reviewers)
GH_USER_ID=$(gh api user --jq '.id')

gh api repos/${GH_ORG}/${GH_REPO}/environments/production \
  --method PUT \
  --input - << EOF
{
  "wait_timer": 5,
  "reviewers": [
    {
      "type": "User",
      "id": ${GH_USER_ID}
    }
  ],
  "deployment_branch_policy": {
    "protected_branches": true,
    "custom_branch_policies": false
  }
}
EOF

echo "Environments created: dev, staging, production"
```

### Verify Environments

```bash
gh api repos/${GH_ORG}/${GH_REPO}/environments --jq '.environments[].name'
```

---

## Phase 6: Run Audit Script and Populate Import Blocks

### 6.1 Run the Audit Script

```bash
cd ../../  # Return to repo root

# Run the audit/discovery script to find existing AWS resources
./scripts/audit.sh --region "${AWS_REGION}" --account-id "${AWS_ACCOUNT_ID}" --output imports/

# Review discovered resources
cat imports/discovered-resources.json | jq '.resources | length'
```

### 6.2 Populate Import Blocks with Real Resource IDs

```bash
# The audit script generates import block templates
# Review and update each environment's imports file

# Example: populate VPC import
cat imports/discovered-resources.json | jq -r '.resources[] | select(.type=="aws_vpc") | .id'

# Update import blocks in the appropriate environment
# Edit envs/dev/imports.tf with real resource IDs
# Edit envs/staging/imports.tf with real resource IDs
# Edit envs/prod/imports.tf with real resource IDs
```

### 6.3 Validate Imports

```bash
# Dry-run import validation for dev
cd envs/dev/
terraform init \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="encrypt=true" \
  -backend-config="kms_key_id=${TF_STATE_KMS_KEY_ID}" \
  -backend-config="dynamodb_table=${TF_STATE_LOCK_TABLE}"

terraform plan -detailed-exitcode
# Exit code 0 = no changes (ideal after import)
# Exit code 2 = changes detected (review carefully)
```

---

## Phase 7: Deploy Dev Environment

### 7.1 Create Feature Branch

```bash
cd ../../  # Return to repo root
git checkout -b feat/deploy-dev-environment
```

### 7.2 Commit Import Blocks and Environment Config

```bash
git add envs/dev/
git commit -m "feat(dev): add import blocks and environment configuration"
git push -u origin feat/deploy-dev-environment
```

### 7.3 Open Pull Request

```bash
gh pr create \
  --title "feat(dev): deploy dev environment" \
  --body "## Summary
- Adds import blocks for existing dev resources
- Configures dev environment Terraform

## Checklist
- [ ] terraform plan shows expected changes
- [ ] No secrets in code
- [ ] tfsec/checkov pass" \
  --base main
```

### 7.4 Merge (Triggers Apply)

```bash
# After CI passes and PR is approved:
gh pr merge --squash --delete-branch

# Monitor the apply workflow
gh run list --workflow=terraform-apply.yml --limit 1
gh run watch
```

---

## Phase 8: Deploy Staging and Production

### 8.1 Deploy Staging

```bash
git checkout main && git pull
git checkout -b feat/deploy-staging-environment

git add envs/staging/
git commit -m "feat(staging): add import blocks and environment configuration"
git push -u origin feat/deploy-staging-environment

gh pr create \
  --title "feat(staging): deploy staging environment" \
  --body "Deploys staging environment with imported resources." \
  --base main

# After approval and CI:
gh pr merge --squash --delete-branch
gh run watch
```

### 8.2 Deploy Production

```bash
git checkout main && git pull
git checkout -b feat/deploy-prod-environment

git add envs/prod/
git commit -m "feat(prod): add import blocks and environment configuration"
git push -u origin feat/deploy-prod-environment

gh pr create \
  --title "feat(prod): deploy production environment" \
  --body "Deploys production environment with imported resources.

Requires production environment approval." \
  --base main

# After approval, CI, AND environment reviewer approval:
gh pr merge --squash --delete-branch

# Production deploy requires manual approval in GitHub Actions
echo "Approve the production deployment in GitHub Actions UI"
gh run watch
```

---

## Phase 9: Decommission Bootstrap Role

> **Only proceed after all environments are successfully deployed and verified.**

```bash
# Unset bootstrap credentials
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN

# Use your normal credentials
aws sts get-caller-identity

# Detach policies from bootstrap role
aws iam detach-role-policy \
  --role-name gitops-bootstrap-temp \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Delete the bootstrap role
aws iam delete-role --role-name gitops-bootstrap-temp

echo "Bootstrap role decommissioned"

# Verify role is gone
aws iam get-role --role-name gitops-bootstrap-temp 2>&1 | grep -q "NoSuchEntity" && \
  echo "PASS: bootstrap role deleted" || \
  echo "WARNING: bootstrap role still exists"
```

---

## Verification

Run these checks to validate the deployment is clean and secure.

### Security Checks

```bash
# Check for hardcoded region references (should use variables)
echo "=== Checking for hardcoded eu-west-2 references ==="
grep -r "eu-west-2" --include="*.tf" --include="*.yml" . && \
  echo "FAIL: Found hardcoded eu-west-2 references" || \
  echo "PASS: No hardcoded eu-west-2 references"

# Check for hardcoded credentials
echo ""
echo "=== Checking for hardcoded credentials ==="
grep -rE "(AKIA[A-Z0-9]{16}|aws_secret_access_key\s*=\s*\"[^\"]+\")" \
  --include="*.tf" --include="*.yml" --include="*.sh" . && \
  echo "FAIL: Found hardcoded credentials" || \
  echo "PASS: No hardcoded credentials found"

# Check for hardcoded AZ names (should use data sources)
echo ""
echo "=== Checking for hardcoded AZ names ==="
grep -rE "(us-east-1[a-f]|us-west-2[a-f]|eu-west-1[a-f])" \
  --include="*.tf" . && \
  echo "FAIL: Found hardcoded AZ names" || \
  echo "PASS: No hardcoded AZ names (using data sources)"
```

### Infrastructure Checks

```bash
# Verify state file is encrypted
aws s3api head-object \
  --bucket "${TF_STATE_BUCKET}" \
  --key "dev/terraform.tfstate" \
  --query "ServerSideEncryption" --output text

# Verify DynamoDB lock table exists
aws dynamodb describe-table \
  --table-name "${TF_STATE_LOCK_TABLE}" \
  --query "Table.TableStatus" --output text

# Verify OIDC provider exists for GitHub Actions
aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')]"
```

### Workflow Checks

```bash
# Verify workflows are running
gh run list --limit 5

# Check environment deployments
gh api repos/${GH_ORG}/${GH_REPO}/deployments --jq '.[].environment'
```

---

## Troubleshooting

| Symptom | Cause | Resolution |
|---------|-------|------------|
| `terraform init` fails with "access denied" | S3 bucket policy does not allow the role | Verify the deploy role has `s3:GetObject`, `s3:PutObject` on the state bucket |
| GitHub Actions fails with "could not assume role" | OIDC trust policy misconfigured | Check the IAM role trust policy includes the correct `sub` claim for the repo/branch |
| `terraform plan` shows unexpected destroys | State file mismatch after import | Run `terraform state list` and compare with plan output; re-import missing resources |
| Branch protection blocks merge | Required status checks not passing | Verify workflow names match the `contexts` in branch protection |
| "Resource already exists" error | Resource not imported before apply | Add `import` block for the existing resource, run `terraform plan` to verify |
| DynamoDB lock not released | Previous apply crashed | Run `terraform force-unlock <LOCK_ID>` (get ID from error message) |
| KMS decrypt error on state | Wrong KMS key ID in backend config | Verify `TF_STATE_KMS_KEY_ID` matches the key used to encrypt the bucket |
| Slack notifications not firing | Webhook URL invalid or secret not set | Test: `curl -X POST -H 'Content-type: application/json' --data '{"text":"test"}' $SLACK_WEBHOOK_URL` |
| Production deploy stuck "waiting" | Environment reviewer has not approved | Check GitHub Actions UI > pending deployments > approve |
| `gh api` returns 404 | Insufficient permissions or wrong repo path | Run `gh auth status` and verify `repo` scope; check org/repo spelling |
| State migration fails | Backend config mismatch | Ensure `backend.tf` values exactly match terraform outputs; try `terraform init -reconfigure` |
| Import block validation errors | Wrong resource ID format | Check AWS docs for the correct import ID format (e.g., VPC uses `vpc-xxx`, not ARN) |

---

## Rollback Procedures

### Rollback a Failed Apply

```bash
# If an apply partially failed, check state
terraform state list

# Revert to previous state version (S3 versioning)
aws s3api list-object-versions \
  --bucket "${TF_STATE_BUCKET}" \
  --prefix "dev/terraform.tfstate" \
  --query "Versions[0:3]"

# Restore previous version
aws s3api copy-object \
  --bucket "${TF_STATE_BUCKET}" \
  --copy-source "${TF_STATE_BUCKET}/dev/terraform.tfstate?versionId=PREVIOUS_VERSION_ID" \
  --key "dev/terraform.tfstate"
```

### Revert a Merged PR

```bash
# Create revert PR
gh pr create \
  --title "revert: undo deployment of XYZ" \
  --body "Reverting due to: <reason>" \
  --base main \
  --head revert-branch
```

---

## Post-Deployment Checklist

- [ ] All three environments (dev, staging, prod) deployed successfully
- [ ] GitHub Actions workflows passing on main
- [ ] Branch protection rules active
- [ ] Production environment requires reviewer approval
- [ ] Slack notifications working
- [ ] Bootstrap IAM role decommissioned
- [ ] No hardcoded credentials in repository
- [ ] State file encrypted at rest
- [ ] DynamoDB lock table operational
- [ ] OIDC provider configured for GitHub Actions
- [ ] All team members have appropriate repository access
