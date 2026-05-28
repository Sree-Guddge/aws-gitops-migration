# envs/dev/imports.tf
# Native Terraform import blocks for brownfield resources in the dev environment.
#
# USAGE:
#   1. Run the audit script to discover actual resource IDs:
#        bash scripts/inventory_export.sh --region us-west-2
#        bash scripts/generate_audit_report.sh
#   2. Replace every placeholder ID (e.g. "vpc-XXXXXXXXXX") with the real ID
#      found in docs/audit-report.md or the AWS CLI commands shown in each comment.
#   3. Run: terraform plan
#      Verify the plan shows zero destructive changes for imported resources.
#   4. Run: terraform apply
#      After a successful apply, remove these import blocks (they are one-shot).
#
# NOTE: Import blocks require Terraform >= 1.5. This repo requires >= 1.7 (see main.tf).
# NOTE: Resources that use count/for_each (subnets, NAT gateways, route tables) require
#       one import block per instance, indexed by count.index or map key.

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------

import {
  to = module.vpc.aws_vpc.this
  id = "vpc-XXXXXXXXXX" # Replace with actual VPC ID from:
  # aws ec2 describe-vpcs --region us-west-2 --filters "Name=tag:Environment,Values=dev" \
  #   --query 'Vpcs[*].VpcId' --output text
}

# ---------------------------------------------------------------------------
# Internet Gateway
# ---------------------------------------------------------------------------

import {
  to = module.vpc.aws_internet_gateway.this
  id = "igw-XXXXXXXXXX" # Replace with actual IGW ID from:
  # aws ec2 describe-internet-gateways --region us-west-2 \
  #   --filters "Name=attachment.vpc-id,Values=<VPC_ID>" \
  #   --query 'InternetGateways[*].InternetGatewayId' --output text
}

# ---------------------------------------------------------------------------
# Public Subnets (one block per subnet; adjust count to match actual number)
# ---------------------------------------------------------------------------

import {
  to = module.vpc.aws_subnet.public[0]
  id = "subnet-XXXXXXXXXX" # Replace with public subnet 0 ID from:
  # aws ec2 describe-subnets --region us-west-2 \
  #   --filters "Name=vpc-id,Values=<VPC_ID>" "Name=tag:Tier,Values=public" \
  #   --query 'sort_by(Subnets, &AvailabilityZone)[0].SubnetId' --output text
}

import {
  to = module.vpc.aws_subnet.public[1]
  id = "subnet-YYYYYYYYYY" # Replace with public subnet 1 ID from:
  # aws ec2 describe-subnets --region us-west-2 \
  #   --filters "Name=vpc-id,Values=<VPC_ID>" "Name=tag:Tier,Values=public" \
  #   --query 'sort_by(Subnets, &AvailabilityZone)[1].SubnetId' --output text
}

import {
  to = module.vpc.aws_subnet.public[2]
  id = "subnet-ZZZZZZZZZZ" # Replace with public subnet 2 ID from:
  # aws ec2 describe-subnets --region us-west-2 \
  #   --filters "Name=vpc-id,Values=<VPC_ID>" "Name=tag:Tier,Values=public" \
  #   --query 'sort_by(Subnets, &AvailabilityZone)[2].SubnetId' --output text
}

# ---------------------------------------------------------------------------
# Private Subnets (one block per subnet; adjust count to match actual number)
# ---------------------------------------------------------------------------

import {
  to = module.vpc.aws_subnet.private[0]
  id = "subnet-AAAAAAAAAA" # Replace with private subnet 0 ID from:
  # aws ec2 describe-subnets --region us-west-2 \
  #   --filters "Name=vpc-id,Values=<VPC_ID>" "Name=tag:Tier,Values=private" \
  #   --query 'sort_by(Subnets, &AvailabilityZone)[0].SubnetId' --output text
}

import {
  to = module.vpc.aws_subnet.private[1]
  id = "subnet-BBBBBBBBBB" # Replace with private subnet 1 ID from:
  # aws ec2 describe-subnets --region us-west-2 \
  #   --filters "Name=vpc-id,Values=<VPC_ID>" "Name=tag:Tier,Values=private" \
  #   --query 'sort_by(Subnets, &AvailabilityZone)[1].SubnetId' --output text
}

import {
  to = module.vpc.aws_subnet.private[2]
  id = "subnet-CCCCCCCCCC" # Replace with private subnet 2 ID from:
  # aws ec2 describe-subnets --region us-west-2 \
  #   --filters "Name=vpc-id,Values=<VPC_ID>" "Name=tag:Tier,Values=private" \
  #   --query 'sort_by(Subnets, &AvailabilityZone)[2].SubnetId' --output text
}

# ---------------------------------------------------------------------------
# NAT Gateway Elastic IPs (one per public subnet / AZ)
# ---------------------------------------------------------------------------

import {
  to = module.vpc.aws_eip.nat[0]
  id = "eipalloc-XXXXXXXXXX" # Replace with EIP allocation ID for NAT GW 0 from:
  # aws ec2 describe-addresses --region us-west-2 \
  #   --filters "Name=tag:Name,Values=*nat-eip-0*" \
  #   --query 'Addresses[*].AllocationId' --output text
}

import {
  to = module.vpc.aws_eip.nat[1]
  id = "eipalloc-YYYYYYYYYY" # Replace with EIP allocation ID for NAT GW 1 from:
  # aws ec2 describe-addresses --region us-west-2 \
  #   --filters "Name=tag:Name,Values=*nat-eip-1*" \
  #   --query 'Addresses[*].AllocationId' --output text
}

import {
  to = module.vpc.aws_eip.nat[2]
  id = "eipalloc-ZZZZZZZZZZ" # Replace with EIP allocation ID for NAT GW 2 from:
  # aws ec2 describe-addresses --region us-west-2 \
  #   --filters "Name=tag:Name,Values=*nat-eip-2*" \
  #   --query 'Addresses[*].AllocationId' --output text
}

# ---------------------------------------------------------------------------
# NAT Gateways (one per AZ)
# ---------------------------------------------------------------------------

import {
  to = module.vpc.aws_nat_gateway.this[0]
  id = "nat-XXXXXXXXXXXXXXXXX" # Replace with NAT Gateway 0 ID from:
  # aws ec2 describe-nat-gateways --region us-west-2 \
  #   --filter "Name=vpc-id,Values=<VPC_ID>" "Name=state,Values=available" \
  #   --query 'sort_by(NatGateways, &SubnetId)[0].NatGatewayId' --output text
}

import {
  to = module.vpc.aws_nat_gateway.this[1]
  id = "nat-YYYYYYYYYYYYYYYYY" # Replace with NAT Gateway 1 ID from:
  # aws ec2 describe-nat-gateways --region us-west-2 \
  #   --filter "Name=vpc-id,Values=<VPC_ID>" "Name=state,Values=available" \
  #   --query 'sort_by(NatGateways, &SubnetId)[1].NatGatewayId' --output text
}

import {
  to = module.vpc.aws_nat_gateway.this[2]
  id = "nat-ZZZZZZZZZZZZZZZZZ" # Replace with NAT Gateway 2 ID from:
  # aws ec2 describe-nat-gateways --region us-west-2 \
  #   --filter "Name=vpc-id,Values=<VPC_ID>" "Name=state,Values=available" \
  #   --query 'sort_by(NatGateways, &SubnetId)[2].NatGatewayId' --output text
}

# ---------------------------------------------------------------------------
# Route Tables
# ---------------------------------------------------------------------------

import {
  to = module.vpc.aws_route_table.public
  id = "rtb-XXXXXXXXXX" # Replace with public route table ID from:
  # aws ec2 describe-route-tables --region us-west-2 \
  #   --filters "Name=vpc-id,Values=<VPC_ID>" "Name=tag:Name,Values=*rt-public*" \
  #   --query 'RouteTables[*].RouteTableId' --output text
}

import {
  to = module.vpc.aws_route_table.private[0]
  id = "rtb-AAAAAAAAAA" # Replace with private route table 0 ID from:
  # aws ec2 describe-route-tables --region us-west-2 \
  #   --filters "Name=vpc-id,Values=<VPC_ID>" "Name=tag:Name,Values=*rt-private-0*" \
  #   --query 'RouteTables[*].RouteTableId' --output text
}

import {
  to = module.vpc.aws_route_table.private[1]
  id = "rtb-BBBBBBBBBB" # Replace with private route table 1 ID from:
  # aws ec2 describe-route-tables --region us-west-2 \
  #   --filters "Name=vpc-id,Values=<VPC_ID>" "Name=tag:Name,Values=*rt-private-1*" \
  #   --query 'RouteTables[*].RouteTableId' --output text
}

import {
  to = module.vpc.aws_route_table.private[2]
  id = "rtb-CCCCCCCCCC" # Replace with private route table 2 ID from:
  # aws ec2 describe-route-tables --region us-west-2 \
  #   --filters "Name=vpc-id,Values=<VPC_ID>" "Name=tag:Name,Values=*rt-private-2*" \
  #   --query 'RouteTables[*].RouteTableId' --output text
}

# ---------------------------------------------------------------------------
# Route Table Associations
# ---------------------------------------------------------------------------

import {
  to = module.vpc.aws_route_table_association.public[0]
  id = "subnet-XXXXXXXXXX/rtb-XXXXXXXXXX" # Replace with: <public_subnet_0_id>/<public_rtb_id>
  # aws ec2 describe-route-tables --region us-west-2 \
  #   --filters "Name=route-table-id,Values=<PUBLIC_RTB_ID>" \
  #   --query 'RouteTables[0].Associations[?SubnetId!=`null`].{SubnetId:SubnetId,AssociationId:RouteTableAssociationId}' --output json
}

import {
  to = module.vpc.aws_route_table_association.public[1]
  id = "subnet-YYYYYYYYYY/rtb-XXXXXXXXXX" # Replace with: <public_subnet_1_id>/<public_rtb_id>
}

import {
  to = module.vpc.aws_route_table_association.public[2]
  id = "subnet-ZZZZZZZZZZ/rtb-XXXXXXXXXX" # Replace with: <public_subnet_2_id>/<public_rtb_id>
}

import {
  to = module.vpc.aws_route_table_association.private[0]
  id = "subnet-AAAAAAAAAA/rtb-AAAAAAAAAA" # Replace with: <private_subnet_0_id>/<private_rtb_0_id>
}

import {
  to = module.vpc.aws_route_table_association.private[1]
  id = "subnet-BBBBBBBBBB/rtb-BBBBBBBBBB" # Replace with: <private_subnet_1_id>/<private_rtb_1_id>
}

import {
  to = module.vpc.aws_route_table_association.private[2]
  id = "subnet-CCCCCCCCCC/rtb-CCCCCCCCCC" # Replace with: <private_subnet_2_id>/<private_rtb_2_id>
}

# ---------------------------------------------------------------------------
# Default Security Group (deny-all, managed by VPC module)
# ---------------------------------------------------------------------------

import {
  to = module.vpc.aws_default_security_group.default
  id = "sg-XXXXXXXXXX" # Replace with the default security group ID for the VPC from:
  # aws ec2 describe-security-groups --region us-west-2 \
  #   --filters "Name=vpc-id,Values=<VPC_ID>" "Name=group-name,Values=default" \
  #   --query 'SecurityGroups[*].GroupId' --output text
}

# ---------------------------------------------------------------------------
# Default Network ACL (deny-all, managed by VPC module)
# ---------------------------------------------------------------------------

import {
  to = module.vpc.aws_default_network_acl.default
  id = "acl-XXXXXXXXXX" # Replace with the default NACL ID for the VPC from:
  # aws ec2 describe-network-acls --region us-west-2 \
  #   --filters "Name=vpc-id,Values=<VPC_ID>" "Name=default,Values=true" \
  #   --query 'NetworkAcls[*].NetworkAclId' --output text
}

# ---------------------------------------------------------------------------
# VPC Flow Log (conditional -- only present if flow_log_bucket_arn is set)
# Uncomment after confirming flow logs are enabled in the dev environment.
# ---------------------------------------------------------------------------

# import {
#   to = module.vpc.aws_flow_log.this[0]
#   id = "fl-XXXXXXXXXX" # Replace with actual flow log ID from:
#   # aws ec2 describe-flow-logs --region us-west-2 \
#   #   --filter "Name=resource-id,Values=<VPC_ID>" \
#   #   --query 'FlowLogs[*].FlowLogId' --output text
# }

# ---------------------------------------------------------------------------
# KMS Key (dev environment key)
# The KMS module uses count based on var.prevent_destroy.
# In dev, prevent_destroy defaults to false, so the resource is aws_kms_key.this_unprotected[0].
# If prevent_destroy = true is set for dev, change to aws_kms_key.this[0].
# ---------------------------------------------------------------------------

import {
  to = module.kms.aws_kms_key.this_unprotected[0]
  id = "mrk-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" # Replace with actual KMS Key ID (not ARN) from:
  # aws kms list-aliases --region us-west-2 \
  #   --query 'Aliases[?AliasName==`alias/dev-terraform-state`].TargetKeyId' --output text
}

import {
  to = module.kms.aws_kms_alias.this
  id = "alias/dev-terraform-state" # Replace with actual alias name if different from:
  # aws kms list-aliases --region us-west-2 \
  #   --query 'Aliases[?contains(AliasName, `dev`)].AliasName' --output text
}

# ---------------------------------------------------------------------------
# CloudTrail Trail
# ---------------------------------------------------------------------------

import {
  to = module.cloudtrail.aws_cloudtrail.this
  id = "dev-trail" # Replace with actual trail name from:
  # aws cloudtrail describe-trails --region us-west-2 \
  #   --query 'trailList[?HomeRegion==`us-west-2`].Name' --output text
}

# CloudTrail log bucket (uses count based on var.prevent_destroy; dev defaults to false
# so the resource is trail_unprotected[0])
import {
  to = module.cloudtrail.aws_s3_bucket.trail_unprotected[0]
  id = "REPLACE-WITH-CLOUDTRAIL-BUCKET-NAME" # Replace with actual bucket name from:
  # aws cloudtrail describe-trails --region us-west-2 \
  #   --query 'trailList[?HomeRegion==`us-west-2`].S3BucketName' --output text
}

# ---------------------------------------------------------------------------
# GuardDuty Detector
# ---------------------------------------------------------------------------

import {
  to = module.guardduty.aws_guardduty_detector.this
  id = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" # Replace with actual detector ID (32-char hex) from:
  # aws guardduty list-detectors --region us-west-2 \
  #   --query 'DetectorIds[0]' --output text
}

# GuardDuty findings bucket (has lifecycle { prevent_destroy = true } in the module)
import {
  to = module.guardduty.aws_s3_bucket.findings
  id = "REPLACE-WITH-GUARDDUTY-FINDINGS-BUCKET-NAME" # Replace with actual bucket name from:
  # aws guardduty list-publishing-destinations --region us-west-2 --detector-id <DETECTOR_ID> \
  #   --query 'Destinations[?DestinationType==`S3`].DestinationProperties.DestinationArn' --output text
  # (extract bucket name from the ARN)
}

# ---------------------------------------------------------------------------
# IAM: GitHub OIDC Provider
# The OIDC provider is a global resource (no region in ARN).
# ---------------------------------------------------------------------------

import {
  to = module.iam.aws_iam_openid_connect_provider.github
  id = "arn:aws:iam::XXXXXXXXXXXX:oidc-provider/token.actions.githubusercontent.com"
  # Replace XXXXXXXXXXXX with your 12-digit AWS account ID from:
  # aws sts get-caller-identity --query 'Account' --output text
}

# ---------------------------------------------------------------------------
# IAM: Deploy Role for dev environment
# The IAM module uses for_each on var.deploy_roles; the key is "dev".
# ---------------------------------------------------------------------------

import {
  to = module.iam.aws_iam_role.deploy["dev"]
  id = "github-deploy-dev" # Replace with actual role name if different from:
  # aws iam list-roles --query 'Roles[?contains(RoleName, `github-deploy-dev`)].RoleName' --output text
}

# ---------------------------------------------------------------------------
# Application S3 Bucket (module.s3)
# The S3 module defaults prevent_destroy = true, so the resource is
# aws_s3_bucket.this[0]. If prevent_destroy is overridden to false in the
# module call, change to aws_s3_bucket.this_unprotected[0].
# ---------------------------------------------------------------------------

import {
  to = module.s3.aws_s3_bucket.this[0]
  id = "REPLACE-WITH-APP-BUCKET-NAME" # Replace with actual bucket name from:
  # aws s3api list-buckets --query 'Buckets[?contains(Name, `app-dev`)].Name' --output text
}

# ===========================================================================
# STATEFUL RESOURCE LIFECYCLE PROTECTION
#
# The following resources require lifecycle { prevent_destroy = true } in their
# corresponding module calls in main.tf. This prevents accidental deletion of
# data-bearing resources during Terraform operations.
#
# For dev environment, stateful resources (RDS, ElastiCache, EFS, S3 with
# replication) should have prevent_destroy enabled in the module call.
# The S3 module already defaults prevent_destroy = true.
# The GuardDuty findings bucket already has prevent_destroy = true in the module.
#
# Requirements: 5.5
# ===========================================================================

# ---------------------------------------------------------------------------
# Example: RDS instance (if present in dev)
# Add to the module "rds" call in main.tf:
#   lifecycle { prevent_destroy = true }
# ---------------------------------------------------------------------------
#
# import {
#   to = module.rds.aws_db_instance.this
#   id = "REPLACE-WITH-RDS-INSTANCE-IDENTIFIER" # from:
#   # aws rds describe-db-instances --region us-west-2 \
#   #   --query 'DBInstances[?TagList[?Key==`Environment`&&Value==`dev`]].DBInstanceIdentifier' \
#   #   --output text
# }

# ---------------------------------------------------------------------------
# Example: ElastiCache cluster (if present in dev)
# Add to the module "elasticache" call in main.tf:
#   lifecycle { prevent_destroy = true }
# ---------------------------------------------------------------------------
#
# import {
#   to = module.elasticache.aws_elasticache_cluster.this
#   id = "REPLACE-WITH-CACHE-CLUSTER-ID" # from:
#   # aws elasticache describe-cache-clusters --region us-west-2 \
#   #   --query 'CacheClusters[?contains(CacheClusterId, `dev`)].CacheClusterId' --output text
# }

# ---------------------------------------------------------------------------
# Example: EFS file system (if present in dev)
# Add to the module "efs" call in main.tf:
#   lifecycle { prevent_destroy = true }
# ---------------------------------------------------------------------------
#
# import {
#   to = module.efs.aws_efs_file_system.this
#   id = "fs-XXXXXXXXXX" # from:
#   # aws efs describe-file-systems --region us-west-2 \
#   #   --query 'FileSystems[?Tags[?Key==`Environment`&&Value==`dev`]].FileSystemId' --output text
# }

# ---------------------------------------------------------------------------
# Example: S3 bucket with replication (if present in dev)
# The module.s3 call already defaults prevent_destroy = true.
# Ensure the module call does NOT override it to false for stateful buckets.
# ---------------------------------------------------------------------------
#
# import {
#   to = module.s3_replicated.aws_s3_bucket.this[0]
#   id = "REPLACE-WITH-REPLICATED-BUCKET-NAME" # from:
#   # aws s3api list-buckets --query 'Buckets[?contains(Name, `replicated`)].Name' --output text
# }
