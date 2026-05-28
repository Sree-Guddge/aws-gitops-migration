# Migration Checklist: AWS eu-west-2 to us-west-2

> This document tracks the migration status of every AWS resource type from eu-west-2 (London) to us-west-2 (Oregon).
> Schema follows the design document per-resource-type format.

---

## Legend

| Field | Description |
|-------|-------------|
| Migration Strategy | `recreate` = destroy and recreate in new region; `update-in-place` = change region variable, no data loss; `import-only` = import existing resource into Terraform state |
| Risk Rating | `Low` = no downtime, reversible; `Medium` = brief disruption possible; `High` = downtime required or data loss risk |
| Stateful | Whether the resource holds persistent data |
| Data Migration Plan | Required if Stateful = yes |
| Import Block Available | Whether Terraform native `import {}` block is supported |
| Downtime Required | Whether migration requires a maintenance window |

---

## Global Resources (No Region Change Required)

> These resources are global in scope and do not need to be migrated between regions.
> They are imported into Terraform state as-is.

| Resource Type | Migration Strategy | Risk Rating | Stateful | Data Migration Plan | Import Block Available | Downtime Required | Notes |
|---------------|-------------------|-------------|----------|--------------------|-----------------------|-------------------|-------|
| `aws_iam_role` | import-only | Low | no | N/A | yes | no | Global resource - no region change required. IAM is region-agnostic. |
| `aws_iam_policy` | import-only | Low | no | N/A | yes | no | Global resource - no region change required. |
| `aws_iam_instance_profile` | import-only | Low | no | N/A | yes | no | Global resource - no region change required. |
| `aws_iam_openid_connect_provider` | import-only | Low | no | N/A | yes | no | Global resource - no region change required. OIDC provider is account-wide. |
| `aws_iam_user` | import-only | Low | no | N/A | yes | no | Global resource - no region change required. |
| `aws_iam_group` | import-only | Low | no | N/A | yes | no | Global resource - no region change required. |
| `aws_route53_zone` | import-only | Low | no | N/A | yes | no | Global resource - no region change required. Route 53 is a global service. |
| `aws_route53_record` | import-only | Low | no | N/A | yes | no | Global resource - no region change required. DNS records are global. |
| `aws_cloudfront_distribution` | import-only | Medium | no | N/A | yes | no | Global resource - no region change required. CloudFront is a global edge service. Origin may need updating if pointing to regional resources. |
| `aws_organizations_organization` | import-only | Low | no | N/A | yes | no | Global resource - no region change required. |
| `aws_organizations_policy` | import-only | Low | no | N/A | yes | no | Global resource - no region change required. SCPs are global. |
| `aws_budgets_budget` | import-only | Low | no | N/A | yes | no | Global resource - no region change required. Budgets are account-wide. |

---

## Regional Resources - Networking

| Resource Type | Migration Strategy | Risk Rating | Stateful | Data Migration Plan | Import Block Available | Downtime Required | Notes |
|---------------|-------------------|-------------|----------|--------------------|-----------------------|-------------------|-------|
| `aws_vpc` | recreate | Medium | no | N/A | yes | no | New VPC created in us-west-2. Old VPC retained until cutover complete. |
| `aws_subnet` | recreate | Medium | no | N/A | yes | no | Subnets created in us-west-2 AZs. CIDR ranges may be reused or changed. |
| `aws_internet_gateway` | recreate | Low | no | N/A | yes | no | Attached to new VPC in us-west-2. |
| `aws_nat_gateway` | recreate | Low | no | N/A | yes | no | New Elastic IPs allocated in us-west-2. |
| `aws_eip` | recreate | Low | no | N/A | yes | no | New EIPs in us-west-2. Old EIPs released after cutover. |
| `aws_route_table` | recreate | Low | no | N/A | yes | no | Associated with new VPC/subnets. |
| `aws_security_group` | recreate | Low | no | N/A | yes | no | Rules replicated in us-west-2 VPC. |
| `aws_network_acl` | recreate | Low | no | N/A | yes | no | Rules replicated in us-west-2 VPC. |
| `aws_vpc_flow_log` | recreate | Low | no | N/A | yes | no | New flow log in us-west-2 delivering to S3. |

---

## Regional Resources - Compute

| Resource Type | Migration Strategy | Risk Rating | Stateful | Data Migration Plan | Import Block Available | Downtime Required | Notes |
|---------------|-------------------|-------------|----------|--------------------|-----------------------|-------------------|-------|
| `aws_instance` | recreate | Medium | no | N/A | yes | yes | Requires maintenance window. AMI must be copied to us-west-2 first. |
| `aws_launch_template` | recreate | Low | no | N/A | yes | no | Updated to reference us-west-2 AMIs and subnets. |
| `aws_autoscaling_group` | recreate | Medium | no | N/A | yes | yes | Brief disruption during ASG replacement. Blue-green recommended. |
| `aws_lb` | recreate | Medium | no | N/A | yes | yes | DNS cutover required. Use weighted Route 53 for zero-downtime. |
| `aws_lb_target_group` | recreate | Low | no | N/A | yes | no | Created alongside new ALB. |

---

## Regional Resources - Storage (Stateful)

| Resource Type | Migration Strategy | Risk Rating | Stateful | Data Migration Plan | Import Block Available | Downtime Required | Notes |
|---------------|-------------------|-------------|----------|--------------------|-----------------------|-------------------|-------|
| `aws_s3_bucket` | update-in-place | Low | yes | **Sync-and-swap**: Enable cross-region replication (CRR) from eu-west-2 to us-west-2 bucket. Verify object parity. Cut over application references. Disable CRR and decommission source. | yes | no | S3 is global namespace. For regional compliance, create new bucket in us-west-2 and use CRR. |
| `aws_db_instance` (RDS) | recreate | High | yes | **Snapshot-and-restore**: Create final snapshot in eu-west-2. Copy snapshot to us-west-2. Restore instance from copied snapshot. Verify data integrity. Update connection strings. | yes | yes | Requires maintenance window. Downtime = snapshot time + restore time (typically 15-60 min depending on DB size). |
| `aws_elasticache_cluster` | recreate | High | yes | **Snapshot-and-restore**: Create backup in eu-west-2. Copy to us-west-2. Create new cluster from backup. Update application endpoints. For Redis with replication, use Global Datastore for near-zero downtime. | yes | yes | Requires maintenance window. |
| `aws_efs_file_system` | recreate | High | yes | **Replication cutover**: Enable EFS replication to us-west-2. Monitor replication lag. During maintenance window, stop writes, verify sync, promote replica, update mount targets. | yes | yes | Requires maintenance window. Downtime depends on final sync lag. |
| `aws_dynamodb_table` | update-in-place | Medium | yes | **Global table**: Enable DynamoDB Global Tables to replicate to us-west-2. Verify replication. Cut over application to us-west-2 endpoint. Remove eu-west-2 replica. | yes | no | Global Tables provide near-zero downtime migration. PAY_PER_REQUEST recommended during migration. |

---

## Regional Resources - Security and Monitoring

| Resource Type | Migration Strategy | Risk Rating | Stateful | Data Migration Plan | Import Block Available | Downtime Required | Notes |
|---------------|-------------------|-------------|----------|--------------------|-----------------------|-------------------|-------|
| `aws_kms_key` | recreate | Medium | no | N/A | yes | no | KMS keys are regional. New keys created in us-west-2. Data re-encrypted with new keys. Multi-region keys can simplify transition. |
| `aws_kms_alias` | recreate | Low | no | N/A | yes | no | Alias points to new us-west-2 key. |
| `aws_cloudtrail` | update-in-place | Low | yes | **No migration needed**: Multi-region trail automatically covers us-west-2. Log bucket may remain in eu-west-2 or be replicated. | yes | no | Multi-region trail already covers all regions. Update S3 log destination if needed. |
| `aws_guardduty_detector` | recreate | Low | no | N/A | yes | no | Enable detector in us-west-2. Historical findings remain in eu-west-2. |
| `aws_config_configuration_recorder` | recreate | Low | no | N/A | yes | no | Enable AWS Config in us-west-2. |
| `aws_securityhub_account` | update-in-place | Low | no | N/A | yes | no | Enable Security Hub in us-west-2. Aggregate findings cross-region. |

---

## Regional Resources - Encryption and Secrets

| Resource Type | Migration Strategy | Risk Rating | Stateful | Data Migration Plan | Import Block Available | Downtime Required | Notes |
|---------------|-------------------|-------------|----------|--------------------|-----------------------|-------------------|-------|
| `aws_secretsmanager_secret` | recreate | Medium | yes | **Sync-and-swap**: Create replica secret in us-west-2 using Secrets Manager multi-region replication. Verify values match. Update application references. | yes | no | Use multi-region secret replication for zero-downtime. |
| `aws_ssm_parameter` | recreate | Low | yes | **Manual copy**: Export parameter values. Create identical parameters in us-west-2. Update application references. | yes | no | No native cross-region replication. Script the copy. |

---

## Summary

| Category | Total Resources | High Risk | Requires Downtime | Stateful |
|----------|----------------|-----------|-------------------|----------|
| Global (no migration) | 12 | 0 | 0 | 0 |
| Networking | 9 | 0 | 0 | 0 |
| Compute | 5 | 0 | 3 | 0 |
| Storage (Stateful) | 5 | 3 | 3 | 5 |
| Security and Monitoring | 6 | 0 | 0 | 1 |
| Encryption and Secrets | 2 | 0 | 0 | 2 |
| **Total** | **39** | **3** | **6** | **8** |

---

## Pre-Migration Checklist

- [ ] Audit report (`docs/audit-report.md`) reviewed and signed off
- [ ] All High-risk resources have scheduled maintenance windows
- [ ] Snapshots/backups verified for all stateful resources
- [ ] Cross-region replication enabled where applicable (S3, DynamoDB, Secrets Manager)
- [ ] DNS TTLs lowered for resources requiring endpoint cutover
- [ ] Rollback plan (`docs/rollback.md`) reviewed and approved
- [ ] Communication sent to stakeholders about maintenance windows
