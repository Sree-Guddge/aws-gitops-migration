#!/usr/bin/env bash
# scripts/inventory_export.sh
# Exports current AWS resource inventory to JSON files under scripts/inventory/<timestamp>/
#
# Usage:
#   bash scripts/inventory_export.sh [--region <region>] [--dry-run]
#
# Flags:
#   --region <region>   AWS region to target (default: us-west-2)
#   --dry-run           Print AWS CLI commands without executing them
#
# Requires: AWS CLI v2, jq

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
REGION="${AWS_REGION:-us-east-1}"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--region <region>] [--dry-run]" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Output directory: scripts/inventory/<timestamp>/
# ---------------------------------------------------------------------------
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
OUTPUT_DIR="scripts/inventory/${TIMESTAMP}"

# ---------------------------------------------------------------------------
# Helper: run or print a command depending on --dry-run
# ---------------------------------------------------------------------------
run() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY-RUN] $*"
  else
    "$@"
  fi
}

# run_capture: capture output to a file (or print the command in dry-run)
run_capture() {
  local outfile="$1"
  shift
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY-RUN] $* > ${outfile}"
  else
    "$@" > "${outfile}"
  fi
}

# ---------------------------------------------------------------------------
# Helper: add "scope" field to every element of a JSON array
# scope: "regional" | "global"
# ---------------------------------------------------------------------------
add_scope() {
  local scope="$1"
  local file="$2"
  if [[ "${DRY_RUN}" == "true" ]]; then
    return
  fi
  if [[ -f "${file}" ]]; then
    local tmp
    tmp=$(mktemp)
    jq --arg scope "${scope}" 'map(. + {"scope": $scope})' "${file}" > "${tmp}"
    mv "${tmp}" "${file}"
  fi
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
if [[ "${DRY_RUN}" == "false" ]]; then
  mkdir -p "${OUTPUT_DIR}"
fi

echo "Exporting inventory to: ${OUTPUT_DIR}/"
echo "  Region : ${REGION}"
echo "  Dry-run: ${DRY_RUN}"
echo ""

# ---------------------------------------------------------------------------
# GLOBAL RESOURCES (scope: global)
# ---------------------------------------------------------------------------

# AWS Organizations structure and SCPs
echo "  -> AWS Organizations structure..."
run_capture "${OUTPUT_DIR}/organizations_roots.json" \
  aws organizations list-roots \
    --query "Roots[*].{Id:Id,Name:Name,Arn:Arn}" \
    --output json
add_scope "global" "${OUTPUT_DIR}/organizations_roots.json"

echo "  -> AWS Organizations OUs..."
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[DRY-RUN] aws organizations list-roots | for each root: aws organizations list-organizational-units-for-parent > ${OUTPUT_DIR}/organizations_ous.json"
else
  ROOT_ID=$(aws organizations list-roots --query "Roots[0].Id" --output text 2>/dev/null || echo "")
  if [[ -n "${ROOT_ID}" ]]; then
    aws organizations list-organizational-units-for-parent \
      --parent-id "${ROOT_ID}" \
      --query "OrganizationalUnits[*].{Id:Id,Name:Name,Arn:Arn}" \
      --output json > "${OUTPUT_DIR}/organizations_ous.json"
    add_scope "global" "${OUTPUT_DIR}/organizations_ous.json"
  else
    echo "[]" > "${OUTPUT_DIR}/organizations_ous.json"
  fi
fi

echo "  -> Service Control Policies (SCPs)..."
run_capture "${OUTPUT_DIR}/organizations_scps.json" \
  aws organizations list-policies \
    --filter SERVICE_CONTROL_POLICY \
    --query "Policies[*].{Id:Id,Name:Name,Arn:Arn,Description:Description}" \
    --output json
add_scope "global" "${OUTPUT_DIR}/organizations_scps.json"

# IAM Roles
echo "  -> IAM roles..."
run_capture "${OUTPUT_DIR}/iam_roles.json" \
  aws iam list-roles \
    --query "Roles[*].{RoleName:RoleName,Arn:Arn,CreateDate:CreateDate,Path:Path}" \
    --output json
add_scope "global" "${OUTPUT_DIR}/iam_roles.json"

# IAM Policies (customer managed)
echo "  -> IAM policies..."
run_capture "${OUTPUT_DIR}/iam_policies.json" \
  aws iam list-policies \
    --scope Local \
    --query "Policies[*].{PolicyName:PolicyName,Arn:Arn,CreateDate:CreateDate}" \
    --output json
add_scope "global" "${OUTPUT_DIR}/iam_policies.json"

# S3 Buckets (global namespace, bucket region noted per bucket)
echo "  -> S3 buckets..."
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[DRY-RUN] aws s3api list-buckets + per-bucket get-bucket-location/get-bucket-versioning > ${OUTPUT_DIR}/s3_buckets.json"
else
  BUCKETS_RAW=$(aws s3api list-buckets \
    --query "Buckets[*].{Name:Name,CreationDate:CreationDate}" \
    --output json)
  ENRICHED="[]"
  while IFS= read -r bucket_name; do
    bucket_region=$(aws s3api get-bucket-location \
      --bucket "${bucket_name}" \
      --query "LocationConstraint" --output text 2>/dev/null || echo "us-east-1")
    # AWS returns "None" for us-east-1
    [[ "${bucket_region}" == "None" ]] && bucket_region="us-east-1"

    versioning=$(aws s3api get-bucket-versioning \
      --bucket "${bucket_name}" \
      --query "Status" --output text 2>/dev/null || echo "Disabled")

    ENRICHED=$(echo "${ENRICHED}" | jq \
      --arg name "${bucket_name}" \
      --arg region "${bucket_region}" \
      --arg versioning "${versioning}" \
      '. + [{"Name": $name, "Region": $region, "Versioning": $versioning, "scope": "global"}]')
  done < <(echo "${BUCKETS_RAW}" | jq -r '.[].Name')
  echo "${ENRICHED}" > "${OUTPUT_DIR}/s3_buckets.json"
fi

# Cost allocation tags
echo "  -> Cost allocation tags..."
run_capture "${OUTPUT_DIR}/cost_allocation_tags.json" \
  aws ce list-cost-allocation-tags \
    --status Active \
    --output json
add_scope "global" "${OUTPUT_DIR}/cost_allocation_tags.json"

# AWS Budgets alerts
echo "  -> AWS Budgets alerts..."
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[DRY-RUN] aws budgets describe-budgets --account-id <ACCOUNT_ID> > ${OUTPUT_DIR}/budgets.json"
else
  ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
  aws budgets describe-budgets \
    --account-id "${ACCOUNT_ID}" \
    --query "Budgets[*].{BudgetName:BudgetName,BudgetType:BudgetType,BudgetLimit:BudgetLimit,TimeUnit:TimeUnit}" \
    --output json > "${OUTPUT_DIR}/budgets.json"
  add_scope "global" "${OUTPUT_DIR}/budgets.json"
fi

# ---------------------------------------------------------------------------
# REGIONAL RESOURCES (scope: regional)
# ---------------------------------------------------------------------------

# VPCs
echo "  -> VPCs..."
run_capture "${OUTPUT_DIR}/vpcs.json" \
  aws ec2 describe-vpcs \
    --region "${REGION}" \
    --query "Vpcs[*].{VpcId:VpcId,CidrBlock:CidrBlock,IsDefault:IsDefault,Tags:Tags}" \
    --output json
add_scope "regional" "${OUTPUT_DIR}/vpcs.json"

# Subnets
echo "  -> Subnets..."
run_capture "${OUTPUT_DIR}/subnets.json" \
  aws ec2 describe-subnets \
    --region "${REGION}" \
    --query "Subnets[*].{SubnetId:SubnetId,VpcId:VpcId,CidrBlock:CidrBlock,AvailabilityZone:AvailabilityZone,Tags:Tags}" \
    --output json
add_scope "regional" "${OUTPUT_DIR}/subnets.json"

# Route Tables
echo "  -> Route tables..."
run_capture "${OUTPUT_DIR}/route_tables.json" \
  aws ec2 describe-route-tables \
    --region "${REGION}" \
    --query "RouteTables[*].{RouteTableId:RouteTableId,VpcId:VpcId,Routes:Routes,Tags:Tags}" \
    --output json
add_scope "regional" "${OUTPUT_DIR}/route_tables.json"

# Network ACLs
echo "  -> Network ACLs..."
run_capture "${OUTPUT_DIR}/network_acls.json" \
  aws ec2 describe-network-acls \
    --region "${REGION}" \
    --query "NetworkAcls[*].{NetworkAclId:NetworkAclId,VpcId:VpcId,IsDefault:IsDefault,Tags:Tags}" \
    --output json
add_scope "regional" "${OUTPUT_DIR}/network_acls.json"

# Security Groups
echo "  -> Security groups..."
run_capture "${OUTPUT_DIR}/security_groups.json" \
  aws ec2 describe-security-groups \
    --region "${REGION}" \
    --query "SecurityGroups[*].{GroupId:GroupId,GroupName:GroupName,VpcId:VpcId,Description:Description}" \
    --output json
add_scope "regional" "${OUTPUT_DIR}/security_groups.json"

# EC2 Instances
echo "  -> EC2 instances..."
run_capture "${OUTPUT_DIR}/ec2_instances.json" \
  aws ec2 describe-instances \
    --region "${REGION}" \
    --query "Reservations[*].Instances[*].{InstanceId:InstanceId,InstanceType:InstanceType,State:State.Name,Tags:Tags,SubnetId:SubnetId,VpcId:VpcId}" \
    --output json
add_scope "regional" "${OUTPUT_DIR}/ec2_instances.json"

# RDS Instances
echo "  -> RDS instances..."
run_capture "${OUTPUT_DIR}/rds_instances.json" \
  aws rds describe-db-instances \
    --region "${REGION}" \
    --query "DBInstances[*].{DBInstanceIdentifier:DBInstanceIdentifier,DBInstanceClass:DBInstanceClass,Engine:Engine,DBInstanceStatus:DBInstanceStatus,MultiAZ:MultiAZ}" \
    --output json
add_scope "regional" "${OUTPUT_DIR}/rds_instances.json"

# Lambda Functions
echo "  -> Lambda functions..."
run_capture "${OUTPUT_DIR}/lambda_functions.json" \
  aws lambda list-functions \
    --region "${REGION}" \
    --query "Functions[*].{FunctionName:FunctionName,Runtime:Runtime,Handler:Handler,LastModified:LastModified}" \
    --output json
add_scope "regional" "${OUTPUT_DIR}/lambda_functions.json"

# KMS Keys (customer managed)
echo "  -> KMS keys..."
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[DRY-RUN] aws kms list-keys --region ${REGION} | per-key describe-key > ${OUTPUT_DIR}/kms_keys.json"
else
  aws kms list-keys --region "${REGION}" --output json | \
    jq ".Keys[].KeyId" -r | while read -r key_id; do
      aws kms describe-key --region "${REGION}" --key-id "${key_id}" \
        --query "KeyMetadata.{KeyId:KeyId,Arn:Arn,Description:Description,KeyState:KeyState,KeyManager:KeyManager}" \
        --output json
    done | jq -s "." > "${OUTPUT_DIR}/kms_keys.json"
  add_scope "regional" "${OUTPUT_DIR}/kms_keys.json"
fi

# CloudTrail Trails
echo "  -> CloudTrail trails..."
run_capture "${OUTPUT_DIR}/cloudtrail_trails.json" \
  aws cloudtrail describe-trails \
    --region "${REGION}" \
    --query "trailList[*].{Name:Name,S3BucketName:S3BucketName,IsMultiRegionTrail:IsMultiRegionTrail,LogFileValidationEnabled:LogFileValidationEnabled}" \
    --output json
add_scope "regional" "${OUTPUT_DIR}/cloudtrail_trails.json"

# GuardDuty Detectors
echo "  -> GuardDuty detectors..."
run_capture "${OUTPUT_DIR}/guardduty_detectors.json" \
  aws guardduty list-detectors \
    --region "${REGION}" \
    --output json
add_scope "regional" "${OUTPUT_DIR}/guardduty_detectors.json"

# AWS Config status
echo "  -> AWS Config recorders..."
run_capture "${OUTPUT_DIR}/config_recorders.json" \
  aws configservice describe-configuration-recorders \
    --region "${REGION}" \
    --output json
add_scope "regional" "${OUTPUT_DIR}/config_recorders.json"

echo "  -> AWS Config recorder status..."
run_capture "${OUTPUT_DIR}/config_recorder_status.json" \
  aws configservice describe-configuration-recorder-status \
    --region "${REGION}" \
    --output json
add_scope "regional" "${OUTPUT_DIR}/config_recorder_status.json"

# Security Hub status
echo "  -> Security Hub..."
run_capture "${OUTPUT_DIR}/securityhub_hub.json" \
  aws securityhub describe-hub \
    --region "${REGION}" \
    --output json
add_scope "regional" "${OUTPUT_DIR}/securityhub_hub.json"

# Existing CI/CD pipelines with AWS credentials
echo "  -> CodePipeline pipelines..."
run_capture "${OUTPUT_DIR}/codepipeline_pipelines.json" \
  aws codepipeline list-pipelines \
    --region "${REGION}" \
    --query "pipelines[*].{name:name,version:version,updated:updated}" \
    --output json
add_scope "regional" "${OUTPUT_DIR}/codepipeline_pipelines.json"

echo "  -> CodeBuild projects..."
run_capture "${OUTPUT_DIR}/codebuild_projects.json" \
  aws codebuild list-projects \
    --region "${REGION}" \
    --output json
add_scope "regional" "${OUTPUT_DIR}/codebuild_projects.json"

# ---------------------------------------------------------------------------
# Metadata summary
# ---------------------------------------------------------------------------
EXPORT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[DRY-RUN] Write ${OUTPUT_DIR}/metadata.json"
else
  cat > "${OUTPUT_DIR}/metadata.json" <<METAEOF
{
  "exported_at": "${EXPORT_TIMESTAMP}",
  "region": "${REGION}",
  "dry_run": false,
  "exported_by": "inventory_export.sh",
  "output_dir": "${OUTPUT_DIR}",
  "files": [
    "organizations_roots.json",
    "organizations_ous.json",
    "organizations_scps.json",
    "iam_roles.json",
    "iam_policies.json",
    "s3_buckets.json",
    "cost_allocation_tags.json",
    "budgets.json",
    "vpcs.json",
    "subnets.json",
    "route_tables.json",
    "network_acls.json",
    "security_groups.json",
    "ec2_instances.json",
    "rds_instances.json",
    "lambda_functions.json",
    "kms_keys.json",
    "cloudtrail_trails.json",
    "guardduty_detectors.json",
    "config_recorders.json",
    "config_recorder_status.json",
    "securityhub_hub.json",
    "codepipeline_pipelines.json",
    "codebuild_projects.json"
  ]
}
METAEOF
fi

echo ""
echo "Inventory export complete: ${OUTPUT_DIR}/"
