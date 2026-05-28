#!/usr/bin/env bash
# scripts/state_migration.sh
# CLI fallback for importing existing AWS resources into Terraform state.
#
# This script is used when native Terraform import blocks (envs/<env>/imports.tf)
# cannot be used. Common reasons native import blocks may not work:
#   - The resource uses a dynamic for_each key that cannot be determined statically
#   - The resource was created outside of any module and has no matching config block yet
#   - Terraform version < 1.5 is required temporarily (import blocks need >= 1.5)
#   - The import requires a multi-step process (e.g., import then state mv)
#
# Run AFTER bootstrap and BEFORE first terraform apply in each environment.
#
# Usage:
#   bash scripts/state_migration.sh --env <dev|staging|prod> [--dry-run]
#
# Flags:
#   --env <environment>   Required. Scope the import to a specific environment (dev, staging, prod).
#   --dry-run             Optional. Print terraform import commands without executing them.
#
# Examples:
#   bash scripts/state_migration.sh --env dev --dry-run
#   bash scripts/state_migration.sh --env prod

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REGION="us-west-2"
DRY_RUN=false
ENV=""

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
usage() {
  echo "Usage: $0 --env <dev|staging|prod> [--dry-run]"
  echo ""
  echo "Flags:"
  echo "  --env <environment>   Required. Target environment (dev, staging, prod)."
  echo "  --dry-run             Optional. Print import commands without executing them."
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --env requires a value (dev, staging, or prod)"
        usage
      fi
      ENV="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "ERROR: Unknown argument: $1"
      usage
      ;;
  esac
done

# Validate --env was provided
if [[ -z "$ENV" ]]; then
  echo "ERROR: --env flag is required."
  usage
fi

# Validate environment value
if [[ "$ENV" != "dev" && "$ENV" != "staging" && "$ENV" != "prod" ]]; then
  echo "ERROR: --env must be one of: dev, staging, prod (got: ${ENV})"
  exit 1
fi

# ---------------------------------------------------------------------------
# Helper function: run or print a terraform import command
# ---------------------------------------------------------------------------
run_import() {
  local resource_addr="$1"
  local resource_id="$2"
  local comment="$3"

  echo ""
  echo "# ${comment}"
  if [[ "$DRY_RUN" == true ]]; then
    echo "terraform import '${resource_addr}' '${resource_id}'"
  else
    echo "Importing: ${resource_addr} <- ${resource_id}"
    terraform import "${resource_addr}" "${resource_id}"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo "============================================================"
echo " State Migration - CLI Import Fallback"
echo "============================================================"
echo "Environment: ${ENV}"
echo "Region:      ${REGION}"
echo "Dry run:     ${DRY_RUN}"
echo "Working dir: envs/${ENV}"
echo "============================================================"
echo ""

if [[ "$DRY_RUN" == true ]]; then
  echo "DRY RUN MODE: Commands will be printed but NOT executed."
  echo ""
fi

# Change to the environment root directory
cd "envs/${ENV}"

# Initialize Terraform (required before import)
if [[ "$DRY_RUN" == false ]]; then
  echo "Initializing Terraform..."
  terraform init
  echo ""
fi

echo "=== CLI IMPORT COMMANDS FOR: ${ENV} ==="
echo ""
echo "These commands import resources that cannot use native import blocks."
echo "Replace placeholder IDs with actual values from your inventory export:"
echo "  scripts/inventory/<timestamp>/ or docs/audit-report.md"
echo ""

# ---------------------------------------------------------------------------
# VPC
# Imports the existing VPC into the vpc module.
# Why CLI fallback: Native import blocks are preferred (see envs/${ENV}/imports.tf).
# Use this CLI fallback when the VPC ID is only known at runtime (e.g., discovered
# by a preceding script) and cannot be hardcoded into an import block.
# ---------------------------------------------------------------------------
run_import \
  "module.vpc.aws_vpc.this" \
  "vpc-XXXXXXXXXX" \
  "VPC: Import existing VPC into the vpc module. CLI fallback needed when VPC ID is discovered dynamically at runtime and cannot be statically declared in an import block."

# ---------------------------------------------------------------------------
# Subnets (public)
# Imports public subnets into the vpc module.
# Why CLI fallback: Subnets use count-based indexing. If the count value is
# computed from a data source, native import blocks cannot resolve the index
# at plan time without the resource already in state.
# ---------------------------------------------------------------------------
run_import \
  "module.vpc.aws_subnet.public[0]" \
  "subnet-XXXXXXXXXX" \
  "Public Subnet 0: Import first public subnet. CLI fallback needed when subnet count is derived from a data source (aws_availability_zones) making static index resolution unreliable."

run_import \
  "module.vpc.aws_subnet.public[1]" \
  "subnet-YYYYYYYYYY" \
  "Public Subnet 1: Import second public subnet. Same reason as above."

run_import \
  "module.vpc.aws_subnet.public[2]" \
  "subnet-ZZZZZZZZZZ" \
  "Public Subnet 2: Import third public subnet. Same reason as above."

# ---------------------------------------------------------------------------
# Subnets (private)
# Imports private subnets into the vpc module.
# Why CLI fallback: Same count-based indexing issue as public subnets.
# ---------------------------------------------------------------------------
run_import \
  "module.vpc.aws_subnet.private[0]" \
  "subnet-AAAAAAAAAA" \
  "Private Subnet 0: Import first private subnet. CLI fallback needed when subnet count is derived from a data source."

run_import \
  "module.vpc.aws_subnet.private[1]" \
  "subnet-BBBBBBBBBB" \
  "Private Subnet 1: Import second private subnet. Same reason as above."

run_import \
  "module.vpc.aws_subnet.private[2]" \
  "subnet-CCCCCCCCCC" \
  "Private Subnet 2: Import third private subnet. Same reason as above."

# ---------------------------------------------------------------------------
# Internet Gateway
# Imports the internet gateway attached to the VPC.
# Why CLI fallback: Native import block is preferred. Use CLI when the IGW ID
# is only available after a preceding VPC import resolves.
# ---------------------------------------------------------------------------
run_import \
  "module.vpc.aws_internet_gateway.this" \
  "igw-XXXXXXXXXX" \
  "Internet Gateway: Import IGW attached to the VPC. CLI fallback useful when IGW ID depends on a prior VPC import completing first."

# ---------------------------------------------------------------------------
# NAT Gateways
# Imports NAT gateways (one per AZ).
# Why CLI fallback: NAT gateways use count based on AZ data source. The index
# mapping between existing NAT gateways and Terraform's count.index may not
# match without manual verification.
# ---------------------------------------------------------------------------
run_import \
  "module.vpc.aws_nat_gateway.this[0]" \
  "nat-XXXXXXXXXXXXXXXXX" \
  "NAT Gateway 0: Import first NAT gateway. CLI fallback needed because count index mapping to existing NAT gateways requires manual AZ-to-index correlation."

run_import \
  "module.vpc.aws_nat_gateway.this[1]" \
  "nat-YYYYYYYYYYYYYYYYY" \
  "NAT Gateway 1: Import second NAT gateway. Same reason as above."

run_import \
  "module.vpc.aws_nat_gateway.this[2]" \
  "nat-ZZZZZZZZZZZZZZZZZ" \
  "NAT Gateway 2: Import third NAT gateway. Same reason as above."

# ---------------------------------------------------------------------------
# Route Tables
# Imports route tables for public and private subnets.
# Why CLI fallback: Private route tables use count indexing tied to AZ count.
# The mapping between existing route tables and Terraform indices requires
# manual verification of which route table serves which AZ.
# ---------------------------------------------------------------------------
run_import \
  "module.vpc.aws_route_table.public" \
  "rtb-XXXXXXXXXX" \
  "Public Route Table: Import the shared public route table. CLI fallback useful when route table ID is discovered dynamically."

run_import \
  "module.vpc.aws_route_table.private[0]" \
  "rtb-AAAAAAAAAA" \
  "Private Route Table 0: Import first private route table. CLI fallback needed because count index mapping requires manual AZ correlation."

run_import \
  "module.vpc.aws_route_table.private[1]" \
  "rtb-BBBBBBBBBB" \
  "Private Route Table 1: Import second private route table. Same reason as above."

run_import \
  "module.vpc.aws_route_table.private[2]" \
  "rtb-CCCCCCCCCC" \
  "Private Route Table 2: Import third private route table. Same reason as above."

# ---------------------------------------------------------------------------
# Security Groups
# Imports the default security group (managed as deny-all by the VPC module).
# Why CLI fallback: The default SG is auto-created by AWS with the VPC. If the
# VPC is imported first, Terraform may not detect the default SG needs import
# until a plan is run, creating a chicken-and-egg ordering issue.
# ---------------------------------------------------------------------------
run_import \
  "module.vpc.aws_default_security_group.default" \
  "sg-XXXXXXXXXX" \
  "Default Security Group: Import VPC default SG (managed as deny-all). CLI fallback needed due to ordering dependency with VPC import."

# ---------------------------------------------------------------------------
# Default Network ACL
# Imports the default NACL (managed as deny-all by the VPC module).
# Why CLI fallback: Same ordering issue as the default security group.
# ---------------------------------------------------------------------------
run_import \
  "module.vpc.aws_default_network_acl.default" \
  "acl-XXXXXXXXXX" \
  "Default Network ACL: Import VPC default NACL (managed as deny-all). CLI fallback needed due to ordering dependency with VPC import."

# ---------------------------------------------------------------------------
# KMS Key
# Imports the environment-specific KMS key used for encryption.
# Why CLI fallback: The KMS module may use conditional resources (count based
# on var.prevent_destroy). The correct resource address depends on the
# environment's prevent_destroy setting, which may not be known until runtime.
# ---------------------------------------------------------------------------
run_import \
  "module.kms.aws_kms_key.this_unprotected[0]" \
  "mrk-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" \
  "KMS Key: Import environment KMS key. CLI fallback needed because the resource address varies based on prevent_destroy setting (this_unprotected vs this)."

run_import \
  "module.kms.aws_kms_alias.this" \
  "alias/${ENV}-terraform-state" \
  "KMS Alias: Import KMS key alias. CLI fallback useful when alias name is environment-parameterized."

# ---------------------------------------------------------------------------
# CloudTrail
# Imports the CloudTrail trail and its log bucket.
# Why CLI fallback: The CloudTrail module may use conditional resource addresses
# based on prevent_destroy. Additionally, the trail name may vary per environment.
# ---------------------------------------------------------------------------
run_import \
  "module.cloudtrail.aws_cloudtrail.this" \
  "${ENV}-trail" \
  "CloudTrail Trail: Import the environment trail. CLI fallback needed because trail name is environment-specific and resource address depends on prevent_destroy setting."

run_import \
  "module.cloudtrail.aws_s3_bucket.trail_unprotected[0]" \
  "REPLACE-WITH-CLOUDTRAIL-BUCKET-NAME" \
  "CloudTrail Log Bucket: Import trail log bucket. CLI fallback needed because resource address varies based on prevent_destroy (trail_unprotected vs trail)."

# ---------------------------------------------------------------------------
# GuardDuty
# Imports the GuardDuty detector and findings export bucket.
# Why CLI fallback: The detector ID is a 32-character hex string that can only
# be discovered via the AWS API. Native import blocks require this value to be
# hardcoded, which is impractical for multi-environment setups where each
# environment has a different detector ID.
# ---------------------------------------------------------------------------
run_import \
  "module.guardduty.aws_guardduty_detector.this" \
  "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" \
  "GuardDuty Detector: Import detector. CLI fallback preferred because detector ID is a 32-char hex only discoverable via API, impractical to hardcode per environment."

run_import \
  "module.guardduty.aws_s3_bucket.findings" \
  "REPLACE-WITH-GUARDDUTY-FINDINGS-BUCKET-NAME" \
  "GuardDuty Findings Bucket: Import findings export bucket. CLI fallback useful when bucket name follows a dynamic naming convention."

# ---------------------------------------------------------------------------
# IAM: OIDC Provider
# Imports the GitHub OIDC provider (global resource, not region-specific).
# Why CLI fallback: The OIDC provider ARN contains the AWS account ID which
# should not be hardcoded in source files. CLI import allows the account ID
# to be injected at runtime.
# ---------------------------------------------------------------------------
run_import \
  "module.iam.aws_iam_openid_connect_provider.github" \
  "arn:aws:iam::XXXXXXXXXXXX:oidc-provider/token.actions.githubusercontent.com" \
  "OIDC Provider: Import GitHub OIDC provider (global). CLI fallback preferred because the ARN contains the AWS account ID which should not be committed to source."

# ---------------------------------------------------------------------------
# IAM: Deploy Role
# Imports the environment-specific deploy role.
# Why CLI fallback: The IAM module uses for_each with dynamic keys. If the
# for_each map is computed from variables that aren't available at import time,
# native import blocks cannot resolve the map key.
# ---------------------------------------------------------------------------
run_import \
  "module.iam.aws_iam_role.deploy[\"${ENV}\"]" \
  "github-deploy-${ENV}" \
  "Deploy Role: Import github-deploy-${ENV} IAM role. CLI fallback needed when the for_each key in the IAM module is computed from variables not available at plan time."

# ---------------------------------------------------------------------------
# Post-import verification
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
if [[ "$DRY_RUN" == true ]]; then
  echo " DRY RUN COMPLETE"
  echo ""
  echo " To execute these imports, re-run without --dry-run:"
  echo "   bash scripts/state_migration.sh --env ${ENV}"
else
  echo " IMPORTS COMPLETE"
fi
echo ""
echo " Next steps:"
echo "   1. Run: terraform plan"
echo "      Verify the plan shows ZERO destructive changes for imported resources."
echo "   2. Run: terraform apply"
echo "      Apply any non-destructive drift corrections."
echo "   3. Remove import blocks from envs/${ENV}/imports.tf (they are one-shot)."
echo "============================================================"