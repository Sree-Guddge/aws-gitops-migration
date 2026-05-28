#!/usr/bin/env bash
# scripts/generate_audit_report.sh
# Reads inventory JSON files produced by inventory_export.sh and generates
# docs/audit-report.md in the Migration Checklist schema.
#
# Usage:
#   bash scripts/generate_audit_report.sh [--inventory-dir <path>] [--output <file>]
#
# Flags:
#   --inventory-dir <path>   Path to the timestamped inventory directory
#                            (default: most recent scripts/inventory/<timestamp>/)
#   --output <file>          Output markdown file (default: docs/audit-report.md)
#
# Requires: jq

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
INVENTORY_DIR=""
OUTPUT_FILE="docs/audit-report.md"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --inventory-dir)
      INVENTORY_DIR="$2"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--inventory-dir <path>] [--output <file>]" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Resolve inventory directory (default: most recent timestamped directory)
# ---------------------------------------------------------------------------
if [[ -z "${INVENTORY_DIR}" ]]; then
  if [[ ! -d "scripts/inventory" ]]; then
    echo "ERROR: scripts/inventory/ not found. Run inventory_export.sh first." >&2
    exit 1
  fi
  # Pick the most recently created subdirectory
  INVENTORY_DIR=$(find scripts/inventory -mindepth 1 -maxdepth 1 -type d | sort | tail -1)
  if [[ -z "${INVENTORY_DIR}" ]]; then
    echo "ERROR: No inventory directories found under scripts/inventory/." >&2
    exit 1
  fi
fi

if [[ ! -d "${INVENTORY_DIR}" ]]; then
  echo "ERROR: Inventory directory not found: ${INVENTORY_DIR}" >&2
  exit 1
fi

echo "Reading inventory from: ${INVENTORY_DIR}"
echo "Writing audit report to: ${OUTPUT_FILE}"

# ---------------------------------------------------------------------------
# Helper: safely read a JSON file; return "[]" if missing or invalid
# ---------------------------------------------------------------------------
read_json() {
  local file="${INVENTORY_DIR}/$1"
  if [[ -f "${file}" ]]; then
    jq '.' "${file}" 2>/dev/null || echo "[]"
  else
    echo "[]"
  fi
}

# ---------------------------------------------------------------------------
# Helper: count items in a JSON array
# ---------------------------------------------------------------------------
count_json() {
  local file="${INVENTORY_DIR}/$1"
  if [[ -f "${file}" ]]; then
    jq 'length' "${file}" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

# ---------------------------------------------------------------------------
# Read metadata
# ---------------------------------------------------------------------------
EXPORTED_AT="unknown"
REGION="unknown"
if [[ -f "${INVENTORY_DIR}/metadata.json" ]]; then
  EXPORTED_AT=$(jq -r '.exported_at // "unknown"' "${INVENTORY_DIR}/metadata.json")
  REGION=$(jq -r '.region // "unknown"' "${INVENTORY_DIR}/metadata.json")
fi

REPORT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ---------------------------------------------------------------------------
# Ensure output directory exists
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "${OUTPUT_FILE}")"

# ---------------------------------------------------------------------------
# Generate the report
# ---------------------------------------------------------------------------
cat > "${OUTPUT_FILE}" <<HEADER
# AWS Infrastructure Audit Report

**Generated:** ${REPORT_DATE}
**Inventory exported at:** ${EXPORTED_AT}
**Target region:** ${REGION}
**Inventory source:** ${INVENTORY_DIR}

---

## Summary

This report enumerates all discovered AWS resources and classifies each by:
- **Migration Strategy**: \`recreate\` | \`update-in-place\` | \`import-only\`
- **Risk Rating**: \`Low\` | \`Medium\` | \`High\`
- **Stateful**: \`yes\` | \`no\`
- **Data Migration Plan**: required when Stateful = yes
- **Import Block Available**: \`yes\` | \`no\`
- **Downtime Required**: \`yes\` | \`no\`

---

## Migration Checklist

| Resource Type | Count | Scope | Migration Strategy | Risk Rating | Stateful | Data Migration Plan | Import Block Available | Downtime Required | Notes |
|---|---|---|---|---|---|---|---|---|---|
HEADER

# ---------------------------------------------------------------------------
# IAM Roles
# ---------------------------------------------------------------------------
IAM_ROLE_COUNT=$(count_json "iam_roles.json")
cat >> "${OUTPUT_FILE}" <<ROW
| aws_iam_role | ${IAM_ROLE_COUNT} | global | import-only | Low | no | N/A | yes | no | IAM is global; no region change required. Use native import blocks. |
ROW

# ---------------------------------------------------------------------------
# IAM Policies
# ---------------------------------------------------------------------------
IAM_POLICY_COUNT=$(count_json "iam_policies.json")
cat >> "${OUTPUT_FILE}" <<ROW
| aws_iam_policy | ${IAM_POLICY_COUNT} | global | import-only | Low | no | N/A | yes | no | IAM is global; no region change required. |
ROW

# ---------------------------------------------------------------------------
# S3 Buckets
# ---------------------------------------------------------------------------
S3_COUNT=$(count_json "s3_buckets.json")
cat >> "${OUTPUT_FILE}" <<ROW
| aws_s3_bucket | ${S3_COUNT} | global | import-only | High | yes | Snapshot-and-restore or sync-and-swap depending on replication config. Enable versioning before migration. | yes | no | S3 is global but bucket region is fixed at creation. Buckets in eu-west-2 must be recreated in us-west-2 with data sync. |
ROW

# ---------------------------------------------------------------------------
# VPCs
# ---------------------------------------------------------------------------
VPC_COUNT=$(count_json "vpcs.json")
cat >> "${OUTPUT_FILE}" <<ROW
| aws_vpc | ${VPC_COUNT} | regional | recreate | Medium | no | N/A | yes | yes | VPCs are region-specific. Must recreate in us-west-2. Coordinate with subnet/SG/route table recreation. |
ROW

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------
SUBNET_COUNT=$(count_json "subnets.json")
cat >> "${OUTPUT_FILE}" <<ROW
| aws_subnet | ${SUBNET_COUNT} | regional | recreate | Medium | no | N/A | yes | yes | Subnets are AZ-specific. Use aws_availability_zones data source; do not hardcode AZ names. |
ROW

# ---------------------------------------------------------------------------
# Route Tables
# ---------------------------------------------------------------------------
RT_COUNT=$(count_json "route_tables.json")
cat >> "${OUTPUT_FILE}" <<ROW
| aws_route_table | ${RT_COUNT} | regional | recreate | Low | no | N/A | yes | yes | Recreate in us-west-2 after VPC and subnet recreation. |
ROW

# ---------------------------------------------------------------------------
# Network ACLs
# ---------------------------------------------------------------------------
NACL_COUNT=$(count_json "network_acls.json")
cat >> "${OUTPUT_FILE}" <<ROW
| aws_network_acl | ${NACL_COUNT} | regional | recreate | Low | no | N/A | yes | yes | Default NACL managed with no rules (deny-all). Custom NACLs recreated in us-west-2. |
ROW

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------
SG_COUNT=$(count_json "security_groups.json")
cat >> "${OUTPUT_FILE}" <<ROW
| aws_security_group | ${SG_COUNT} | regional | recreate | Medium | no | N/A | yes | yes | Recreate in us-west-2. Review all ingress/egress rules for region-specific references. |
ROW

# ---------------------------------------------------------------------------
# EC2 Instances
# ---------------------------------------------------------------------------
EC2_COUNT=$(count_json "ec2_instances.json")
cat >> "${OUTPUT_FILE}" <<ROW
| aws_instance | ${EC2_COUNT} | regional | recreate | High | yes | Snapshot EBS volumes before termination. Restore from snapshot in us-west-2. | yes | yes | AMI IDs are region-specific. Create new AMIs or copy existing AMIs to us-west-2. |
ROW

# ---------------------------------------------------------------------------
# RDS Instances
# ---------------------------------------------------------------------------
RDS_COUNT=$(count_json "rds_instances.json")
cat >> "${OUTPUT_FILE}" <<ROW
| aws_db_instance | ${RDS_COUNT} | regional | recreate | High | yes | Snapshot-and-restore: create final snapshot, restore in us-west-2, update connection strings. lifecycle { prevent_destroy = true } required. | yes | yes | RDS is stateful. Schedule maintenance window. Validate data integrity post-restore before cutover. |
ROW

# ---------------------------------------------------------------------------
# Lambda Functions
# ---------------------------------------------------------------------------
LAMBDA_COUNT=$(count_json "lambda_functions.json")
cat >> "${OUTPUT_FILE}" <<ROW
| aws_lambda_function | ${LAMBDA_COUNT} | regional | recreate | Low | no | N/A | yes | no | Lambda deployment packages are region-agnostic. Redeploy to us-west-2. Update any region-specific environment variables. |
ROW

# ---------------------------------------------------------------------------
# KMS Keys
# ---------------------------------------------------------------------------
KMS_COUNT=$(count_json "kms_keys.json")
cat >> "${OUTPUT_FILE}" <<ROW
| aws_kms_key | ${KMS_COUNT} | regional | recreate | High | yes | KMS keys cannot be moved between regions. Create new keys in us-west-2. Re-encrypt all data encrypted with eu-west-2 keys. | yes | yes | Plan re-encryption of S3 objects, EBS volumes, and RDS snapshots. lifecycle { prevent_destroy = true } required. |
ROW

# ---------------------------------------------------------------------------
# CloudTrail
# ---------------------------------------------------------------------------
CT_COUNT=$(count_json "cloudtrail_trails.json")
cat >> "${OUTPUT_FILE}" <<ROW
| aws_cloudtrail | ${CT_COUNT} | regional | update-in-place | Low | no | N/A | yes | no | Enable is_multi_region_trail=true to cover us-west-2. Update S3 log bucket to us-west-2. |
ROW

# ---------------------------------------------------------------------------
# GuardDuty
# ---------------------------------------------------------------------------
GD_COUNT=$(count_json "guardduty_detectors.json")
cat >> "${OUTPUT_FILE}" <<ROW
| aws_guardduty_detector | ${GD_COUNT} | regional | update-in-place | Low | no | N/A | yes | no | Enable GuardDuty in us-west-2. Configure findings export to central S3 bucket. |
ROW

# ---------------------------------------------------------------------------
# AWS Config
# ---------------------------------------------------------------------------
CONFIG_COUNT=$(count_json "config_recorders.json")
cat >> "${OUTPUT_FILE}" <<ROW
| aws_config_configuration_recorder | ${CONFIG_COUNT} | regional | update-in-place | Low | no | N/A | yes | no | Enable AWS Config in us-west-2. Review existing rules for region-specific references. |
ROW

# ---------------------------------------------------------------------------
# Security Hub
# ---------------------------------------------------------------------------
cat >> "${OUTPUT_FILE}" <<ROW
| aws_securityhub_account | 1 | regional | update-in-place | Low | no | N/A | yes | no | Enable Security Hub in us-west-2. Re-enable standards (CIS, AWS Foundational). |
ROW

# ---------------------------------------------------------------------------
# AWS Budgets
# ---------------------------------------------------------------------------
BUDGET_COUNT=$(count_json "budgets.json")
cat >> "${OUTPUT_FILE}" <<ROW
| aws_budgets_budget | ${BUDGET_COUNT} | global | import-only | Low | no | N/A | yes | no | Budgets are account-level (global). Import existing budgets; no region change required. |
ROW

# ---------------------------------------------------------------------------
# CodePipeline
# ---------------------------------------------------------------------------
CP_COUNT=$(count_json "codepipeline_pipelines.json")
cat >> "${OUTPUT_FILE}" <<ROW
| aws_codepipeline | ${CP_COUNT} | regional | recreate | Medium | no | N/A | yes | yes | Existing CI/CD pipelines with AWS credentials must be migrated to OIDC. Recreate in us-west-2 or replace with GitHub Actions. |
ROW

# ---------------------------------------------------------------------------
# CodeBuild
# ---------------------------------------------------------------------------
CB_COUNT=$(count_json "codebuild_projects.json")
cat >> "${OUTPUT_FILE}" <<ROW
| aws_codebuild_project | ${CB_COUNT} | regional | recreate | Medium | no | N/A | yes | yes | Recreate CodeBuild projects in us-west-2. Update any region-specific environment variables or artifact locations. |
ROW

# ---------------------------------------------------------------------------
# Organizations / SCPs
# ---------------------------------------------------------------------------
SCP_COUNT=$(count_json "organizations_scps.json")
cat >> "${OUTPUT_FILE}" <<ROW
| aws_organizations_policy (SCP) | ${SCP_COUNT} | global | import-only | Low | no | N/A | yes | no | SCPs are global (Organizations). No region change required. Import into Terraform state. |
ROW

# ---------------------------------------------------------------------------
# Cost Allocation Tags
# ---------------------------------------------------------------------------
TAG_COUNT=$(count_json "cost_allocation_tags.json")
cat >> "${OUTPUT_FILE}" <<ROW
| Cost Allocation Tags | ${TAG_COUNT} | global | update-in-place | Low | no | N/A | no | no | Cost allocation tags are account-level. Review and update tag keys to align with new tagging schema. |
ROW

# ---------------------------------------------------------------------------
# Detailed resource listings
# ---------------------------------------------------------------------------
cat >> "${OUTPUT_FILE}" <<SECTION

---

## Detailed Resource Inventory

### IAM Roles (${IAM_ROLE_COUNT} found)

> **Scope:** global — no region change required

SECTION

if [[ -f "${INVENTORY_DIR}/iam_roles.json" ]]; then
  echo "| Role Name | ARN | Created |" >> "${OUTPUT_FILE}"
  echo "|---|---|---|" >> "${OUTPUT_FILE}"
  jq -r '.[] | "| \(.RoleName // "N/A") | \(.Arn // "N/A") | \(.CreateDate // "N/A") |"' \
    "${INVENTORY_DIR}/iam_roles.json" >> "${OUTPUT_FILE}" 2>/dev/null || true
fi

cat >> "${OUTPUT_FILE}" <<SECTION

### S3 Buckets (${S3_COUNT} found)

> **Scope:** global — bucket region is fixed at creation; buckets in eu-west-2 require data migration

SECTION

if [[ -f "${INVENTORY_DIR}/s3_buckets.json" ]]; then
  echo "| Bucket Name | Region | Versioning |" >> "${OUTPUT_FILE}"
  echo "|---|---|---|" >> "${OUTPUT_FILE}"
  jq -r '.[] | "| \(.Name // "N/A") | \(.Region // "N/A") | \(.Versioning // "Disabled") |"' \
    "${INVENTORY_DIR}/s3_buckets.json" >> "${OUTPUT_FILE}" 2>/dev/null || true
fi

cat >> "${OUTPUT_FILE}" <<SECTION

### VPCs (${VPC_COUNT} found)

> **Scope:** regional — must be recreated in us-west-2

SECTION

if [[ -f "${INVENTORY_DIR}/vpcs.json" ]]; then
  echo "| VPC ID | CIDR Block | Default |" >> "${OUTPUT_FILE}"
  echo "|---|---|---|" >> "${OUTPUT_FILE}"
  jq -r '.[] | "| \(.VpcId // "N/A") | \(.CidrBlock // "N/A") | \(.IsDefault // false) |"' \
    "${INVENTORY_DIR}/vpcs.json" >> "${OUTPUT_FILE}" 2>/dev/null || true
fi

cat >> "${OUTPUT_FILE}" <<SECTION

### EC2 Instances (${EC2_COUNT} found)

> **Scope:** regional — stateful; EBS snapshots required before migration

SECTION

if [[ -f "${INVENTORY_DIR}/ec2_instances.json" ]]; then
  echo "| Instance ID | Type | State | VPC ID |" >> "${OUTPUT_FILE}"
  echo "|---|---|---|---|" >> "${OUTPUT_FILE}"
  # ec2_instances.json may be a nested array (Reservations[*].Instances[*])
  jq -r 'flatten | .[] | "| \(.InstanceId // "N/A") | \(.InstanceType // "N/A") | \(.State // "N/A") | \(.VpcId // "N/A") |"' \
    "${INVENTORY_DIR}/ec2_instances.json" >> "${OUTPUT_FILE}" 2>/dev/null || true
fi

cat >> "${OUTPUT_FILE}" <<SECTION

### RDS Instances (${RDS_COUNT} found)

> **Scope:** regional — stateful; snapshot-and-restore required; schedule maintenance window

SECTION

if [[ -f "${INVENTORY_DIR}/rds_instances.json" ]]; then
  echo "| DB Identifier | Class | Engine | Status | Multi-AZ |" >> "${OUTPUT_FILE}"
  echo "|---|---|---|---|---|" >> "${OUTPUT_FILE}"
  jq -r '.[] | "| \(.DBInstanceIdentifier // "N/A") | \(.DBInstanceClass // "N/A") | \(.Engine // "N/A") | \(.DBInstanceStatus // "N/A") | \(.MultiAZ // false) |"' \
    "${INVENTORY_DIR}/rds_instances.json" >> "${OUTPUT_FILE}" 2>/dev/null || true
fi

cat >> "${OUTPUT_FILE}" <<SECTION

### KMS Keys (${KMS_COUNT} found)

> **Scope:** regional — cannot be moved; new keys required in us-west-2; re-encryption of all data required

SECTION

if [[ -f "${INVENTORY_DIR}/kms_keys.json" ]]; then
  echo "| Key ID | ARN | Description | State | Manager |" >> "${OUTPUT_FILE}"
  echo "|---|---|---|---|---|" >> "${OUTPUT_FILE}"
  jq -r '.[] | "| \(.KeyId // "N/A") | \(.Arn // "N/A") | \(.Description // "") | \(.KeyState // "N/A") | \(.KeyManager // "N/A") |"' \
    "${INVENTORY_DIR}/kms_keys.json" >> "${OUTPUT_FILE}" 2>/dev/null || true
fi

cat >> "${OUTPUT_FILE}" <<SECTION

### CloudTrail Trails (${CT_COUNT} found)

> **Scope:** regional — update to multi-region trail targeting us-west-2

SECTION

if [[ -f "${INVENTORY_DIR}/cloudtrail_trails.json" ]]; then
  echo "| Trail Name | S3 Bucket | Multi-Region | Log Validation |" >> "${OUTPUT_FILE}"
  echo "|---|---|---|---|" >> "${OUTPUT_FILE}"
  jq -r '.[] | "| \(.Name // "N/A") | \(.S3BucketName // "N/A") | \(.IsMultiRegionTrail // false) | \(.LogFileValidationEnabled // false) |"' \
    "${INVENTORY_DIR}/cloudtrail_trails.json" >> "${OUTPUT_FILE}" 2>/dev/null || true
fi

cat >> "${OUTPUT_FILE}" <<SECTION

### AWS Budgets (${BUDGET_COUNT} found)

> **Scope:** global — no region change required; import into Terraform state

SECTION

if [[ -f "${INVENTORY_DIR}/budgets.json" ]]; then
  echo "| Budget Name | Type | Limit | Time Unit |" >> "${OUTPUT_FILE}"
  echo "|---|---|---|---|" >> "${OUTPUT_FILE}"
  jq -r '.[] | "| \(.BudgetName // "N/A") | \(.BudgetType // "N/A") | \(.BudgetLimit.Amount // "N/A") \(.BudgetLimit.Unit // "") | \(.TimeUnit // "N/A") |"' \
    "${INVENTORY_DIR}/budgets.json" >> "${OUTPUT_FILE}" 2>/dev/null || true
fi

cat >> "${OUTPUT_FILE}" <<SECTION

### CI/CD Pipelines (${CP_COUNT} CodePipeline + ${CB_COUNT} CodeBuild found)

> **Scope:** regional — migrate to GitHub Actions with OIDC; remove any hardcoded AWS credentials

SECTION

if [[ -f "${INVENTORY_DIR}/codepipeline_pipelines.json" ]]; then
  echo "**CodePipeline:**" >> "${OUTPUT_FILE}"
  echo "" >> "${OUTPUT_FILE}"
  echo "| Pipeline Name | Version | Last Updated |" >> "${OUTPUT_FILE}"
  echo "|---|---|---|" >> "${OUTPUT_FILE}"
  jq -r '.[] | "| \(.name // "N/A") | \(.version // "N/A") | \(.updated // "N/A") |"' \
    "${INVENTORY_DIR}/codepipeline_pipelines.json" >> "${OUTPUT_FILE}" 2>/dev/null || true
fi

cat >> "${OUTPUT_FILE}" <<SECTION

---

## Global Resources — No Region Change Required

The following resource types are AWS global services and do not require a region migration:

| Resource Type | Reason |
|---|---|
| IAM Roles & Policies | IAM is a global service; roles and policies are not region-specific |
| S3 Bucket Namespace | S3 bucket names are globally unique; however, bucket region is fixed at creation |
| AWS Organizations / SCPs | Organizations is a global service managed from the management account |
| AWS Budgets | Budgets are account-level, not region-specific |
| Route 53 | DNS is global (not enumerated in this audit — add if applicable) |
| CloudFront | CDN is global (not enumerated in this audit — add if applicable) |

---

## Stateful Resources — Data Migration Required

The following resources hold persistent data and require a data migration plan:

| Resource Type | Migration Approach | RTO Estimate | Notes |
|---|---|---|---|
| aws_db_instance (RDS) | Snapshot-and-restore | 2–4 hours | Create final snapshot in eu-west-2; restore in us-west-2; validate data; update connection strings |
| aws_s3_bucket (with data) | Sync-and-swap | Variable | Use aws s3 sync or S3 Replication to copy objects; validate checksums; update bucket policies |
| aws_kms_key | Re-encryption | 1–2 hours per dataset | Create new CMK in us-west-2; re-encrypt S3 objects, EBS snapshots, RDS snapshots |
| aws_instance (EBS volumes) | Snapshot-and-restore | 1–2 hours | Create EBS snapshots; copy to us-west-2; restore; validate |

---

## Next Steps

1. Review this report and confirm resource counts match expectations
2. For each stateful resource, schedule a maintenance window and document the snapshot IDs
3. Run \`scripts/inventory_export.sh --region us-west-2\` to confirm the target region is empty (or document existing resources)
4. Proceed to bootstrap: \`bash scripts/bootstrap.md\` → \`terraform -chdir=infra/bootstrap apply\`
5. Add native \`import\` blocks to \`envs/dev/imports.tf\` for all resources listed above
6. Run \`terraform plan\` and verify zero destructive changes before applying

SECTION

echo "Audit report written to: ${OUTPUT_FILE}"
