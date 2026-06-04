#!/usr/bin/env bash
# tests/smoke_prod.sh
# Production smoke tests -- stricter checks including lifecycle protection and budgets.
# Verifies VPC, state backend, security services, deploy role, region compliance,
# prevent_destroy on stateful resources, and AWS Budgets alert.

set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
ENV="prod"
PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "=== Smoke Tests: ${ENV} (${REGION}) ==="

# --------------------------------------------------------------------------
# 1. VPC exists with correct CIDR
# --------------------------------------------------------------------------
VPC_INFO=$(aws ec2 describe-vpcs --region "${REGION}" \
  --filters "Name=tag:Environment,Values=${ENV}" \
  --query "Vpcs[0].[State,CidrBlock]" --output text 2>/dev/null || echo "NONE NONE")
VPC_STATE=$(echo "${VPC_INFO}" | awk '{print $1}')
VPC_CIDR=$(echo "${VPC_INFO}" | awk '{print $2}')

if [ "${VPC_STATE}" = "available" ]; then
  pass "VPC is available with CIDR ${VPC_CIDR}"
else
  fail "VPC not found or not available (state: ${VPC_STATE})"
fi

# --------------------------------------------------------------------------
# 2. Private subnets exist (at least 3 for multi-AZ)
# --------------------------------------------------------------------------
SUBNET_COUNT=$(aws ec2 describe-subnets --region "${REGION}" \
  --filters "Name=tag:Environment,Values=${ENV}" "Name=tag:Tier,Values=private" \
  --query "length(Subnets)" --output text 2>/dev/null || echo "0")
[ "${SUBNET_COUNT}" -ge 3 ] && pass "Private subnets exist (${SUBNET_COUNT})" || fail "Expected >=3 private subnets, got ${SUBNET_COUNT}"

# --------------------------------------------------------------------------
# 3. State S3 bucket exists with versioning enabled and public access blocked
# --------------------------------------------------------------------------
STATE_BUCKET=$(aws ssm get-parameter --region "${REGION}" \
  --name "/terraform/state-bucket-name" --query "Parameter.Value" --output text 2>/dev/null || echo "")

if [ -n "${STATE_BUCKET}" ]; then
  # Check bucket exists
  if aws s3api head-bucket --bucket "${STATE_BUCKET}" 2>/dev/null; then
    pass "State S3 bucket '${STATE_BUCKET}' exists"
  else
    fail "State S3 bucket '${STATE_BUCKET}' does not exist or is not accessible"
  fi

  # Check versioning is enabled
  VERSIONING=$(aws s3api get-bucket-versioning --bucket "${STATE_BUCKET}" \
    --query "Status" --output text 2>/dev/null || echo "Disabled")
  if [ "${VERSIONING}" = "Enabled" ]; then
    pass "State S3 bucket versioning is enabled"
  else
    fail "State S3 bucket versioning is NOT enabled (got: ${VERSIONING})"
  fi

  # Check public access block (all four settings must be true)
  PUBLIC_ACCESS=$(aws s3api get-public-access-block --bucket "${STATE_BUCKET}" \
    --query "PublicAccessBlockConfiguration.[BlockPublicAcls,BlockPublicPolicy,IgnorePublicAcls,RestrictPublicBuckets]" \
    --output text 2>/dev/null || echo "")
  ALL_BLOCKED=true
  for val in ${PUBLIC_ACCESS}; do
    if [ "${val}" != "True" ]; then
      ALL_BLOCKED=false
      break
    fi
  done
  if [ "${ALL_BLOCKED}" = "true" ] && [ -n "${PUBLIC_ACCESS}" ]; then
    pass "State S3 bucket public access is fully blocked"
  else
    fail "State S3 bucket public access block is incomplete (got: ${PUBLIC_ACCESS})"
  fi
else
  fail "State bucket SSM parameter '/terraform/state-bucket-name' not found"
fi

# --------------------------------------------------------------------------
# 4. DynamoDB lock table exists
# --------------------------------------------------------------------------
LOCK_TABLE_STATUS=$(aws dynamodb describe-table --region "${REGION}" \
  --table-name "terraform-state-lock" \
  --query "Table.TableStatus" --output text 2>/dev/null || echo "NONE")
if [ "${LOCK_TABLE_STATUS}" = "ACTIVE" ]; then
  pass "DynamoDB lock table 'terraform-state-lock' exists and is ACTIVE"
else
  fail "DynamoDB lock table 'terraform-state-lock' not found or not active (status: ${LOCK_TABLE_STATUS})"
fi

# --------------------------------------------------------------------------
# 5. CloudTrail trail is active and IsMultiRegionTrail=true
# --------------------------------------------------------------------------
TRAIL_LOGGING=$(aws cloudtrail get-trail-status --region "${REGION}" \
  --name "${ENV}-trail" \
  --query "IsLogging" --output text 2>/dev/null || echo "false")
TRAIL_MULTI_REGION=$(aws cloudtrail describe-trails --region "${REGION}" \
  --trail-name-list "${ENV}-trail" \
  --query "trailList[0].IsMultiRegionTrail" --output text 2>/dev/null || echo "false")

if [ "${TRAIL_LOGGING}" = "True" ]; then
  pass "CloudTrail '${ENV}-trail' is actively logging"
else
  fail "CloudTrail '${ENV}-trail' is NOT logging (got: ${TRAIL_LOGGING})"
fi

if [ "${TRAIL_MULTI_REGION}" = "True" ] || [ "${TRAIL_MULTI_REGION}" = "true" ]; then
  pass "CloudTrail '${ENV}-trail' is multi-region"
else
  fail "CloudTrail '${ENV}-trail' IsMultiRegionTrail is not true (got: ${TRAIL_MULTI_REGION})"
fi

# --------------------------------------------------------------------------
# 6. GuardDuty detector is enabled
# --------------------------------------------------------------------------
DETECTOR_ID=$(aws guardduty list-detectors --region "${REGION}" \
  --query "DetectorIds[0]" --output text 2>/dev/null || echo "NONE")

if [ "${DETECTOR_ID}" != "NONE" ] && [ "${DETECTOR_ID}" != "None" ] && [ -n "${DETECTOR_ID}" ]; then
  DETECTOR_STATUS=$(aws guardduty get-detector --region "${REGION}" \
    --detector-id "${DETECTOR_ID}" \
    --query "Status" --output text 2>/dev/null || echo "DISABLED")
  if [ "${DETECTOR_STATUS}" = "ENABLED" ]; then
    pass "GuardDuty detector is enabled (ID: ${DETECTOR_ID})"
  else
    fail "GuardDuty detector exists but is not enabled (status: ${DETECTOR_STATUS})"
  fi
else
  fail "GuardDuty detector not found in ${REGION}"
fi

# --------------------------------------------------------------------------
# 7. Deploy role 'github-deploy-prod' exists
# --------------------------------------------------------------------------
ROLE_ARN=$(aws iam get-role --role-name "github-deploy-prod" \
  --query "Role.Arn" --output text 2>/dev/null || echo "NONE")
if [ "${ROLE_ARN}" != "NONE" ] && [ -n "${ROLE_ARN}" ]; then
  pass "Deploy role 'github-deploy-prod' exists (${ROLE_ARN})"
else
  fail "Deploy role 'github-deploy-prod' not found"
fi

# --------------------------------------------------------------------------
# 8. No eu-west-2 references in source files
# --------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

EU_WEST_MATCHES=$(grep -r 'eu-west-2' "${REPO_ROOT}/modules/" "${REPO_ROOT}/envs/" "${REPO_ROOT}/ci/" \
  --include='*.tf' --include='*.yml' 2>/dev/null | wc -l || echo "0")
EU_WEST_MATCHES=$(echo "${EU_WEST_MATCHES}" | tr -d '[:space:]')

if [ "${EU_WEST_MATCHES}" -eq 0 ]; then
  pass "No 'eu-west-2' references found in modules/, envs/, ci/ (.tf and .yml files)"
else
  fail "Found ${EU_WEST_MATCHES} 'eu-west-2' reference(s) in modules/, envs/, ci/ -- all should be us-west-2"
fi

# --------------------------------------------------------------------------
# 9. lifecycle.prevent_destroy is set on stateful resources (prod-only)
# --------------------------------------------------------------------------
# Check via terraform state show that stateful resources have prevent_destroy
# This verifies the Terraform configuration includes lifecycle protection
STATEFUL_TYPES=("aws_s3_bucket" "aws_dynamodb_table" "aws_db_instance" "aws_elasticache_cluster" "aws_efs_file_system")
PREVENT_DESTROY_MISSING=0

for resource_type in "${STATEFUL_TYPES[@]}"; do
  # List resources of this type in state
  RESOURCES=$(terraform -chdir="${REPO_ROOT}/envs/prod" state list 2>/dev/null | grep "^.*${resource_type}\." || true)
  for resource in ${RESOURCES}; do
    # Check if prevent_destroy is set by examining the state
    STATE_OUTPUT=$(terraform -chdir="${REPO_ROOT}/envs/prod" state show "${resource}" 2>/dev/null || echo "")
    if echo "${STATE_OUTPUT}" | grep -q "prevent_destroy"; then
      : # prevent_destroy found - OK
    else
      echo "  WARNING: ${resource} may not have lifecycle.prevent_destroy set"
      PREVENT_DESTROY_MISSING=$((PREVENT_DESTROY_MISSING+1))
    fi
  done
done

if [ "${PREVENT_DESTROY_MISSING}" -eq 0 ]; then
  pass "All stateful resources have lifecycle.prevent_destroy configured"
else
  fail "${PREVENT_DESTROY_MISSING} stateful resource(s) missing lifecycle.prevent_destroy"
fi

# Also verify prevent_destroy in source .tf files for prod
PREVENT_DESTROY_IN_SOURCE=$(grep -r 'prevent_destroy\s*=\s*true' "${REPO_ROOT}/envs/prod/" \
  --include='*.tf' 2>/dev/null | wc -l || echo "0")
PREVENT_DESTROY_IN_SOURCE=$(echo "${PREVENT_DESTROY_IN_SOURCE}" | tr -d '[:space:]')

if [ "${PREVENT_DESTROY_IN_SOURCE}" -ge 1 ]; then
  pass "prevent_destroy = true found in prod Terraform source (${PREVENT_DESTROY_IN_SOURCE} occurrence(s))"
else
  fail "No 'prevent_destroy = true' found in envs/prod/ .tf files"
fi

# --------------------------------------------------------------------------
# 10. AWS Budgets alert exists (prod-only)
# --------------------------------------------------------------------------
BUDGET_COUNT=$(aws budgets describe-budgets --account-id "$(aws sts get-caller-identity --query Account --output text)" \
  --query "length(Budgets)" --output text 2>/dev/null || echo "0")

if [ "${BUDGET_COUNT}" -ge 1 ]; then
  pass "AWS Budgets alert exists (${BUDGET_COUNT} budget(s) configured)"
else
  fail "No AWS Budgets alerts found -- at least one budget should be configured for prod"
fi

# --------------------------------------------------------------------------------
# 11. IAM Identity Center (Entra ID SSO) permission sets exist
# --------------------------------------------------------------------------------
# Requires the SSO instance to be enabled and infra/sso applied. Skips gracefully
# if IAM Identity Center is not enabled in this account.
SSO_INSTANCE_ARN=$(aws sso-admin list-instances \
  --query "Instances[0].InstanceArn" --output text 2>/dev/null || echo "None")

if [ "${SSO_INSTANCE_ARN}" = "None" ] || [ -z "${SSO_INSTANCE_ARN}" ]; then
  fail "IAM Identity Center is not enabled -- Entra ID SSO (initiative 2) cannot be validated"
else
  pass "IAM Identity Center instance found (${SSO_INSTANCE_ARN})"

  PS_NAMES=$(aws sso-admin list-permission-sets --instance-arn "${SSO_INSTANCE_ARN}" \
    --query "PermissionSets" --output text 2>/dev/null || echo "")

  RESOLVED=""
  for ARN in ${PS_NAMES}; do
    NAME=$(aws sso-admin describe-permission-set --instance-arn "${SSO_INSTANCE_ARN}" \
      --permission-set-arn "${ARN}" --query "PermissionSet.Name" --output text 2>/dev/null || echo "")
    RESOLVED="${RESOLVED} ${NAME}"
  done

  for EXPECTED in AdministratorAccess PowerUserAccess ReadOnly Billing Developer RegionalAdmin; do
    if echo "${RESOLVED}" | grep -qw "${EXPECTED}"; then
      pass "Permission set '${EXPECTED}' exists"
    else
      fail "Permission set '${EXPECTED}' missing -- run terraform apply in infra/sso"
    fi
  done
fi
# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1
