#!/usr/bin/env bash
#
# setup.sh - Automated local setup for AWS GitOps Migration
#
# Usage:
#   ./scripts/setup.sh --org <github-org> --repo <repo-name> --account-id <aws-account-id> [--region <aws-region>] [--dry-run]
#
# Description:
#   Automates the initial setup of the AWS GitOps infrastructure including:
#   - Git repository initialization
#   - GitHub repository creation
#   - Terraform bootstrap (S3 state, DynamoDB lock, IAM roles)
#   - GitHub secrets configuration
#   - Branch protection rules
#   - GitHub environment creation
#
# Prerequisites:
#   aws, terraform, gh, git, jq must be installed and authenticated.
#

set -euo pipefail

# =============================================================================
# Configuration & Defaults
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Defaults
REGION="us-west-2"
DRY_RUN=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_step() {
  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  $1${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

run_cmd() {
  local description="$1"
  shift
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo -e "${YELLOW}[DRY-RUN]${NC} ${description}"
    echo "  Command: $*"
    echo ""
  else
    log_info "${description}"
    if [[ "${VERBOSE}" == "true" ]]; then
      echo "  Command: $*"
    fi
    "$@"
  fi
}

usage() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Automates the local setup for AWS GitOps Migration.

Required:
  --org <org>            GitHub organization name
  --repo <repo>          GitHub repository name
  --account-id <id>      AWS account ID (12-digit number)

Optional:
  --region <region>      AWS region (default: us-west-2)
  --dry-run              Print commands without executing them
  --verbose              Show detailed command output
  --help                 Show this help message

Examples:
  # Full setup
  $(basename "$0") --org my-company --repo aws-infra --account-id 123456789012

  # Preview what would happen
  $(basename "$0") --org my-company --repo aws-infra --account-id 123456789012 --dry-run

  # Use a different region
  $(basename "$0") --org my-company --repo aws-infra --account-id 123456789012 --region eu-west-1
EOF
  exit 0
}

# =============================================================================
# Argument Parsing
# =============================================================================

GH_ORG=""
GH_REPO=""
AWS_ACCOUNT_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)
      GH_ORG="$2"
      shift 2
      ;;
    --repo)
      GH_REPO="$2"
      shift 2
      ;;
    --account-id)
      AWS_ACCOUNT_ID="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --help|-h)
      usage
      ;;
    *)
      log_error "Unknown option: $1"
      usage
      ;;
  esac
done

# =============================================================================
# Validation
# =============================================================================

validate_inputs() {
  local errors=0

  if [[ -z "${GH_ORG}" ]]; then
    log_error "Missing required flag: --org"
    errors=$((errors + 1))
  fi

  if [[ -z "${GH_REPO}" ]]; then
    log_error "Missing required flag: --repo"
    errors=$((errors + 1))
  fi

  if [[ -z "${AWS_ACCOUNT_ID}" ]]; then
    log_error "Missing required flag: --account-id"
    errors=$((errors + 1))
  elif ! [[ "${AWS_ACCOUNT_ID}" =~ ^[0-9]{12}$ ]]; then
    log_error "Invalid AWS account ID: must be a 12-digit number"
    errors=$((errors + 1))
  fi

  if ! [[ "${REGION}" =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]]; then
    log_error "Invalid AWS region format: ${REGION}"
    errors=$((errors + 1))
  fi

  if [[ ${errors} -gt 0 ]]; then
    echo ""
    usage
  fi
}

validate_prerequisites() {
  log_step "Validating Prerequisites"

  local missing=0
  local tools=("aws" "terraform" "gh" "git" "jq")

  for tool in "${tools[@]}"; do
    if command -v "${tool}" &> /dev/null; then
      local version
      case "${tool}" in
        aws) version=$(aws --version 2>&1 | head -1) ;;
        terraform) version=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1) ;;
        gh) version=$(gh --version | head -1) ;;
        git) version=$(git --version) ;;
        jq) version=$(jq --version) ;;
      esac
      log_success "${tool} found: ${version}"
    else
      log_error "${tool} is not installed"
      missing=$((missing + 1))
    fi
  done

  if [[ ${missing} -gt 0 ]]; then
    log_error "Please install missing tools before continuing."
    exit 1
  fi

  # Validate authentication
  echo ""
  log_info "Checking AWS authentication..."
  if aws sts get-caller-identity &> /dev/null; then
    local caller_id
    caller_id=$(aws sts get-caller-identity --query 'Arn' --output text)
    log_success "AWS authenticated as: ${caller_id}"
  else
    log_error "AWS CLI is not authenticated. Run 'aws configure' or set credentials."
    exit 1
  fi

  log_info "Checking GitHub CLI authentication..."
  if gh auth status &> /dev/null; then
    log_success "GitHub CLI authenticated"
  else
    log_error "GitHub CLI is not authenticated. Run 'gh auth login'."
    exit 1
  fi
}

# =============================================================================
# Setup Steps
# =============================================================================

init_git_repo() {
  log_step "Step 1: Initialize Git Repository"

  cd "${REPO_ROOT}"

  if [[ -d ".git" ]]; then
    log_info "Git repository already initialized"
  else
    run_cmd "Initializing git repository" git init
    run_cmd "Creating main branch" git checkout -b main
  fi

  # Ensure .gitignore exists
  if [[ ! -f ".gitignore" ]]; then
    run_cmd "Creating .gitignore" cat > .gitignore << 'GITIGNORE'
# Terraform
*.tfstate
*.tfstate.*
*.tfplan
.terraform/
.terraform.lock.hcl
crash.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# Environment variables
.env
*.env

# OS files
.DS_Store
Thumbs.db

# IDE
.idea/
.vscode/
*.swp
*.swo
GITIGNORE
  fi
}

create_github_repo() {
  log_step "Step 2: Create GitHub Repository"

  # Check if repo already exists
  if gh repo view "${GH_ORG}/${GH_REPO}" &> /dev/null; then
    log_warn "Repository ${GH_ORG}/${GH_REPO} already exists. Skipping creation."
  else
    run_cmd "Creating GitHub repository: ${GH_ORG}/${GH_REPO}" \
      gh repo create "${GH_ORG}/${GH_REPO}" \
        --private \
        --description "AWS infrastructure managed via Terraform + GitOps" \
        --source "${REPO_ROOT}" \
        --push
  fi
}

push_code() {
  log_step "Step 3: Push Code to GitHub"

  cd "${REPO_ROOT}"

  # Set remote if not already set
  if ! git remote get-url origin &> /dev/null; then
    run_cmd "Adding remote origin" \
      git remote add origin "https://github.com/${GH_ORG}/${GH_REPO}.git"
  fi

  # Stage and commit if there are changes
  if [[ -n "$(git status --porcelain)" ]]; then
    run_cmd "Staging all files" git add -A
    run_cmd "Creating initial commit" git commit -m "feat: initial infrastructure scaffolding"
  fi

  run_cmd "Pushing to origin/main" git push -u origin main
}

run_terraform_bootstrap() {
  log_step "Step 4: Run Terraform Bootstrap"

  local bootstrap_dir="${REPO_ROOT}/infra/bootstrap"

  if [[ ! -d "${bootstrap_dir}" ]]; then
    log_error "Bootstrap directory not found: ${bootstrap_dir}"
    exit 1
  fi

  cd "${bootstrap_dir}"

  run_cmd "Running terraform init" terraform init

  run_cmd "Running terraform plan" \
    terraform plan -out=bootstrap.tfplan \
      -var="account_id=${AWS_ACCOUNT_ID}" \
      -var="region=${REGION}" \
      -var="github_org=${GH_ORG}" \
      -var="github_repo=${GH_REPO}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would run: terraform apply bootstrap.tfplan"
  else
    log_warn "About to apply Terraform bootstrap. This will create:"
    echo "  - S3 bucket for Terraform state"
    echo "  - DynamoDB table for state locking"
    echo "  - KMS key for state encryption"
    echo "  - IAM roles for GitHub Actions (dev, staging, prod)"
    echo "  - OIDC provider for GitHub Actions"
    echo ""
    read -r -p "Continue? [y/N] " confirm
    if [[ "${confirm}" =~ ^[Yy]$ ]]; then
      terraform apply bootstrap.tfplan
    else
      log_error "Bootstrap cancelled by user."
      exit 1
    fi
  fi
}

read_terraform_outputs() {
  log_step "Step 5: Read Terraform Outputs"

  local bootstrap_dir="${REPO_ROOT}/infra/bootstrap"
  cd "${bootstrap_dir}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would read terraform outputs:"
    echo "  TF_STATE_BUCKET=<from terraform output>"
    echo "  TF_STATE_KMS_KEY_ARN=<from terraform output>"
    echo "  TF_STATE_KMS_KEY_ID=<from terraform output>"
    echo "  TF_STATE_LOCK_TABLE=<from terraform output>"
    echo "  AWS_DEPLOY_ROLE_DEV=<from terraform output>"
    echo "  AWS_DEPLOY_ROLE_STAGING=<from terraform output>"
    echo "  AWS_DEPLOY_ROLE_PROD=<from terraform output>"

    # Set placeholder values for dry-run
    TF_STATE_BUCKET="<state-bucket>"
    TF_STATE_KMS_KEY_ARN="<kms-key-arn>"
    TF_STATE_KMS_KEY_ID="<kms-key-id>"
    TF_STATE_LOCK_TABLE="<lock-table>"
    AWS_DEPLOY_ROLE_DEV="<dev-role-arn>"
    AWS_DEPLOY_ROLE_STAGING="<staging-role-arn>"
    AWS_DEPLOY_ROLE_PROD="<prod-role-arn>"
  else
    TF_STATE_BUCKET=$(terraform output -raw state_bucket_name)
    TF_STATE_KMS_KEY_ARN=$(terraform output -raw kms_key_arn)
    TF_STATE_KMS_KEY_ID=$(terraform output -raw kms_key_id)
    TF_STATE_LOCK_TABLE=$(terraform output -raw dynamodb_table_name)
    AWS_DEPLOY_ROLE_DEV=$(terraform output -raw deploy_role_arn_dev)
    AWS_DEPLOY_ROLE_STAGING=$(terraform output -raw deploy_role_arn_staging)
    AWS_DEPLOY_ROLE_PROD=$(terraform output -raw deploy_role_arn_prod)

    log_success "State Bucket:       ${TF_STATE_BUCKET}"
    log_success "KMS Key ARN:        ${TF_STATE_KMS_KEY_ARN}"
    log_success "KMS Key ID:         ${TF_STATE_KMS_KEY_ID}"
    log_success "Lock Table:         ${TF_STATE_LOCK_TABLE}"
    log_success "Dev Role ARN:       ${AWS_DEPLOY_ROLE_DEV}"
    log_success "Staging Role ARN:   ${AWS_DEPLOY_ROLE_STAGING}"
    log_success "Prod Role ARN:      ${AWS_DEPLOY_ROLE_PROD}"
  fi
}

set_github_secrets() {
  log_step "Step 6: Configure GitHub Secrets"

  local repo="${GH_ORG}/${GH_REPO}"

  run_cmd "Setting TF_STATE_BUCKET" \
    gh secret set TF_STATE_BUCKET --body "${TF_STATE_BUCKET}" --repo "${repo}"

  run_cmd "Setting TF_STATE_KMS_KEY_ARN" \
    gh secret set TF_STATE_KMS_KEY_ARN --body "${TF_STATE_KMS_KEY_ARN}" --repo "${repo}"

  run_cmd "Setting TF_STATE_KMS_KEY_ID" \
    gh secret set TF_STATE_KMS_KEY_ID --body "${TF_STATE_KMS_KEY_ID}" --repo "${repo}"

  run_cmd "Setting TF_STATE_LOCK_TABLE" \
    gh secret set TF_STATE_LOCK_TABLE --body "${TF_STATE_LOCK_TABLE}" --repo "${repo}"

  run_cmd "Setting AWS_DEPLOY_ROLE_DEV" \
    gh secret set AWS_DEPLOY_ROLE_DEV --body "${AWS_DEPLOY_ROLE_DEV}" --repo "${repo}"

  run_cmd "Setting AWS_DEPLOY_ROLE_STAGING" \
    gh secret set AWS_DEPLOY_ROLE_STAGING --body "${AWS_DEPLOY_ROLE_STAGING}" --repo "${repo}"

  run_cmd "Setting AWS_DEPLOY_ROLE_PROD" \
    gh secret set AWS_DEPLOY_ROLE_PROD --body "${AWS_DEPLOY_ROLE_PROD}" --repo "${repo}"

  # Prompt for Slack webhook
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would prompt for SLACK_WEBHOOK_URL and set it as a secret"
  else
    echo ""
    read -r -p "Enter Slack Webhook URL (or press Enter to skip): " slack_url
    if [[ -n "${slack_url}" ]]; then
      gh secret set SLACK_WEBHOOK_URL --body "${slack_url}" --repo "${repo}"
      log_success "SLACK_WEBHOOK_URL set"
    else
      log_warn "Skipping SLACK_WEBHOOK_URL - you can set it later with:"
      echo "  gh secret set SLACK_WEBHOOK_URL --body '<url>' --repo ${repo}"
    fi
  fi

  echo ""
  log_info "Verifying secrets..."
  if [[ "${DRY_RUN}" != "true" ]]; then
    gh secret list --repo "${repo}"
  fi
}

configure_branch_protection() {
  log_step "Step 7: Configure Branch Protection"

  local repo="${GH_ORG}/${GH_REPO}"

  local protection_payload='{
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
  }'

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would configure branch protection on main:"
    echo "${protection_payload}" | jq .
  else
    echo "${protection_payload}" | gh api "repos/${repo}/branches/main/protection" \
      --method PUT \
      --input -
    log_success "Branch protection configured for main"
  fi
}

create_github_environments() {
  log_step "Step 8: Create GitHub Environments"

  local repo="${GH_ORG}/${GH_REPO}"

  # Dev environment
  run_cmd "Creating dev environment" \
    gh api "repos/${repo}/environments/dev" \
      --method PUT \
      --input - <<< '{
        "deployment_branch_policy": {
          "protected_branches": false,
          "custom_branch_policies": true
        }
      }'

  if [[ "${DRY_RUN}" != "true" ]]; then
    gh api "repos/${repo}/environments/dev/deployment-branch-policies" \
      --method POST \
      --field name="*" 2>/dev/null || true
  fi

  # Staging environment
  run_cmd "Creating staging environment" \
    gh api "repos/${repo}/environments/staging" \
      --method PUT \
      --input - <<< '{
        "deployment_branch_policy": {
          "protected_branches": true,
          "custom_branch_policies": false
        }
      }'

  # Production environment with reviewers
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would create production environment with reviewer approval"
  else
    local gh_user_id
    gh_user_id=$(gh api user --jq '.id')

    gh api "repos/${repo}/environments/production" \
      --method PUT \
      --input - << EOF
{
  "wait_timer": 5,
  "reviewers": [
    {
      "type": "User",
      "id": ${gh_user_id}
    }
  ],
  "deployment_branch_policy": {
    "protected_branches": true,
    "custom_branch_policies": false
  }
}
EOF
    log_success "Production environment created with reviewer: user ID ${gh_user_id}"
  fi

  log_success "All environments created: dev, staging, production"
}

print_next_steps() {
  log_step "Setup Complete - Next Steps"

  echo -e "${GREEN}The following has been configured:${NC}"
  echo "  - GitHub repository: ${GH_ORG}/${GH_REPO}"
  echo "  - Terraform state backend (S3 + DynamoDB + KMS)"
  echo "  - GitHub secrets for CI/CD"
  echo "  - Branch protection on main"
  echo "  - GitHub environments (dev, staging, production)"
  echo ""
  echo -e "${YELLOW}Next steps:${NC}"
  echo ""
  echo "  1. Run the audit script to discover existing AWS resources:"
  echo "     ./scripts/audit.sh --region ${REGION} --account-id ${AWS_ACCOUNT_ID} --output imports/"
  echo ""
  echo "  2. Populate import blocks with real resource IDs:"
  echo "     - Edit envs/dev/imports.tf"
  echo "     - Edit envs/staging/imports.tf"
  echo "     - Edit envs/prod/imports.tf"
  echo ""
  echo "  3. Open your first PR to deploy the dev environment:"
  echo "     git checkout -b feat/deploy-dev-environment"
  echo "     git add envs/dev/"
  echo "     git commit -m 'feat(dev): add import blocks and environment configuration'"
  echo "     git push -u origin feat/deploy-dev-environment"
  echo "     gh pr create --title 'feat(dev): deploy dev environment' --base main"
  echo ""
  echo "  4. After dev is stable, repeat for staging and production."
  echo ""
  echo "  5. Decommission the bootstrap role (see docs/deployment-runbook.md Phase 9)"
  echo ""
  echo -e "${BLUE}Full deployment guide: docs/deployment-runbook.md${NC}"
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║          AWS GitOps Migration - Setup Script                ║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo -e "${YELLOW}*** DRY-RUN MODE: No changes will be made ***${NC}"
    echo ""
  fi

  echo "Configuration:"
  echo "  Organization:  ${GH_ORG}"
  echo "  Repository:    ${GH_REPO}"
  echo "  AWS Account:   ${AWS_ACCOUNT_ID}"
  echo "  AWS Region:    ${REGION}"
  echo "  Dry Run:       ${DRY_RUN}"
  echo ""

  validate_prerequisites
  init_git_repo
  create_github_repo
  push_code
  run_terraform_bootstrap
  read_terraform_outputs
  set_github_secrets
  configure_branch_protection
  create_github_environments
  print_next_steps
}

# Validate inputs before running
validate_inputs
main