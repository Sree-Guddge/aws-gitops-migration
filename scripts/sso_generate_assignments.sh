#!/usr/bin/env bash
# scripts/sso_generate_assignments.sh
# Generates infra/sso/terraform.tfvars `account_assignments` HCL by looking up
# SCIM-synced Entra group IDs in the IAM Identity Center Identity Store.
#
# Prerequisite: Entra ID SCIM provisioning must have synced the aws-* groups
# (see docs/sso-setup.md Part 2). Until then this script reports which groups
# are missing.
#
# Usage:
#   bash scripts/sso_generate_assignments.sh <ACCOUNT_ID> [<ACCOUNT_ID> ...]
#
# Example:
#   bash scripts/sso_generate_assignments.sh 286684483345
#
# The Entra-group -> permission-set mapping convention (edit GROUP_MAP to change):
#   aws-admins      -> AdministratorAccess
#   aws-powerusers  -> PowerUserAccess
#   aws-readonly    -> ReadOnly
#   aws-billing     -> Billing
#   aws-developers  -> Developer

set -euo pipefail

# SSO is homed in us-east-1 (independent of the us-west-2 workload region).
SSO_REGION="${SSO_REGION:-us-east-1}"

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <ACCOUNT_ID> [<ACCOUNT_ID> ...]" >&2
  exit 1
fi
ACCOUNTS=("$@")

# group display name -> permission set name
declare -A GROUP_MAP=(
  ["aws-admins"]="AdministratorAccess"
  ["aws-powerusers"]="PowerUserAccess"
  ["aws-readonly"]="ReadOnly"
  ["aws-billing"]="Billing"
  ["aws-developers"]="Developer"
)

IDENTITY_STORE_ID="$(aws sso-admin list-instances --region "$SSO_REGION" \
  --query 'Instances[0].IdentityStoreId' --output text)"

if [ -z "$IDENTITY_STORE_ID" ] || [ "$IDENTITY_STORE_ID" = "None" ]; then
  echo "ERROR: No IAM Identity Center instance found in $SSO_REGION" >&2
  exit 1
fi

echo "# Identity Store: $IDENTITY_STORE_ID  (region: $SSO_REGION)" >&2
echo "account_assignments = ["

missing=0
for group in "${!GROUP_MAP[@]}"; do
  ps="${GROUP_MAP[$group]}"
  gid="$(aws identitystore list-groups --region "$SSO_REGION" \
    --identity-store-id "$IDENTITY_STORE_ID" \
    --filters "AttributePath=DisplayName,AttributeValue=${group}" \
    --query 'Groups[0].GroupId' --output text 2>/dev/null || echo "None")"

  if [ -z "$gid" ] || [ "$gid" = "None" ]; then
    echo "  # WARNING: group '${group}' not found in Identity Store (SCIM not synced yet) -> permission set '${ps}'" >&2
    missing=$((missing+1))
    continue
  fi

  for acct in "${ACCOUNTS[@]}"; do
    echo "  {"
    echo "    group_id       = \"${gid}\"  # ${group}"
    echo "    account_id     = \"${acct}\""
    echo "    permission_set = \"${ps}\""
    echo "  },"
  done
done

echo "]"

if [ "$missing" -gt 0 ]; then
  echo "" >&2
  echo "${missing} group(s) were not found. Complete Entra SCIM provisioning (docs/sso-setup.md Part 2) and re-run." >&2
fi