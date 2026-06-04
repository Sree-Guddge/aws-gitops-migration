# AWS Infrastructure Audit Report

**Generated:** PENDING — run `bash scripts/generate_audit_report.sh` to populate with live data
**Target region:** us-west-2
**Inventory source:** scripts/inventory/ (latest timestamped directory)

---

## Summary

This report enumerates all discovered AWS resources and classifies each by:
- **Migration Strategy**: `recreate` | `update-in-place` | `import-only`
- **Risk Rating**: `Low` | `Medium` | `High`
- **Stateful**: `yes` | `no`
- **Data Migration Plan**: required when Stateful = yes
- **Import Block Available**: `yes` | `no`
- **Downtime Required**: `yes` | `no`

> **Note:** Replace placeholder IDs in `envs/dev/imports.tf` with actual resource IDs
> discovered by running `bash scripts/inventory_export.sh --region us-west-2`.

---

## Migration Checklist

| Resource Type | Scope | Migration Strategy | Risk Rating | Stateful | Data Migration Plan | Import Block Available | Downtime Required | Notes |
|---|---|---|---|---|---|---|---|---|
| aws_iam_role | global | import-only | Low | no | N/A | yes | no | IAM is global; no region change required. Use native import blocks. |
| aws_iam_policy | global | import-only | Low | no | N/A | yes | no | IAM is global; no region change required. |
| aws_iam_openid_connect_provider | global | import-only | Low | no | N/A | yes | no | OIDC provider is account-wide. |
| aws_vpc | regional | recreate | Medium | no | N/A | yes | yes | VPCs are region-specific. Recreate in us-west-2. |
| aws_subnet | regional | recreate | Medium | no | N/A | yes | yes | Subnets are AZ-specific. Use aws_availability_zones data source. |
| aws_internet_gateway | regional | recreate | Low | no | N/A | yes | no | Attached to new VPC in us-west-2. |
| aws_nat_gateway | regional | recreate | Low | no | N/A | yes | no | New Elastic IPs allocated in us-west-2. |
| aws_eip | regional | recreate | Low | no | N/A | yes | no | New EIPs in us-west-2. |
| aws_route_table | regional | recreate | Low | no | N/A | yes | yes | Associated with new VPC/subnets. |
| aws_security_group | regional | recreate | Medium | no | N/A | yes | yes | Default SG managed with deny-all. |
| aws_network_acl | regional | recreate | Low | no | N/A | yes | yes | Default NACL managed with deny-all. |
| aws_kms_key | regional | recreate | Medium | no | N/A | yes | no | KMS keys are regional. New keys created in us-west-2. |
| aws_kms_alias | regional | recreate | Low | no | N/A | yes | no | Alias points to new us-west-2 key. |
| aws_cloudtrail | regional | update-in-place | Low | no | N/A | yes | no | Multi-region trail covers us-west-2. |
| aws_guardduty_detector | regional | update-in-place | Low | no | N/A | yes | no | Enable detector in us-west-2. |
| aws_s3_bucket | global | import-only | High | yes | Sync-and-swap with cross-region replication. | yes | no | Bucket region is fixed at creation. |
| aws_db_instance | regional | recreate | High | yes | Snapshot-and-restore. lifecycle { prevent_destroy = true } required. | yes | yes | Schedule maintenance window. |
| aws_elasticache_cluster | regional | recreate | High | yes | Snapshot-and-restore or Global Datastore. lifecycle { prevent_destroy = true } required. | yes | yes | Schedule maintenance window. |
| aws_efs_file_system | regional | recreate | High | yes | EFS replication cutover. lifecycle { prevent_destroy = true } required. | yes | yes | Schedule maintenance window. |
| aws_vpc_flow_log | regional | recreate | Low | no | N/A | yes | no | Conditional; enabled when flow_log_bucket_arn is set. |
