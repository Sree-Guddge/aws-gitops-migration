# Post-Migration Cutover Checklist

## Pre-Cutover (Complete Before Production Apply)

### Infrastructure
- [ ] All resources inventoried (scripts/inventory/prod/ exists and is current)
- [ ] All resources imported into Terraform state (terraform plan shows no unexpected creates)
- [ ] Dev environment apply successful and smoke tests passing
- [ ] Staging environment apply successful and smoke tests passing
- [ ] Entra SSO login tested in staging with non-admin user
- [ ] SCIM sync verified in staging (groups and users visible in IAM Identity Center)

### Security
- [ ] No AWS access keys in any repo or workflow logs (grep -r "AKIA" . returns nothing)
- [ ] All S3 buckets have block public access enabled
- [ ] All S3 buckets have SSE-KMS encryption
- [ ] KMS key policies reviewed and approved by Security Lead
- [ ] IAM roles follow least privilege (Access Analyzer findings reviewed)
- [ ] CloudTrail enabled and logging to encrypted S3 bucket
- [ ] GuardDuty enabled in all accounts

### CI/CD
- [ ] Branch protection rules configured (PR required, CODEOWNERS enforced)
- [ ] GitHub environments configured with required reviewers for prod
- [ ] PR plan workflow passing on a test PR
- [ ] OIDC roles verified (aws sts get-caller-identity shows role, not user)

---

## Cutover Day

### T-1 Hour
- [ ] Notify stakeholders of maintenance window
- [ ] Take RDS snapshots of all production databases
- [ ] Verify rollback procedure is documented and tested

### T-0 (Production Apply)
- [ ] Open PR with prod changes
- [ ] Review terraform plan output carefully
- [ ] Get required approvals
- [ ] Merge PR
- [ ] Monitor GitHub Actions workflow
- [ ] Run smoke tests: bash tests/smoke_prod.sh

### T+1 Hour
- [ ] Verify all application health checks pass
- [ ] Verify SSO login works for at least one user from each group
- [ ] Verify CloudTrail is logging new events
- [ ] Verify GuardDuty has no new critical findings

---

## Post-Cutover (Within 48 Hours)

### Cleanup
- [ ] Remove TerraformBootstrapRole (temporary bootstrap IAM role)
- [ ] Remove any remaining direct IAM users (migrate to SSO)
- [ ] Verify no long-lived access keys remain active

### Documentation
- [ ] Update architecture diagram if topology changed
- [ ] Confirm inventory export reflects new state
- [ ] Archive pre-migration inventory

### Sign-off

| Item | Verified by | Date |
|------|-------------|------|
| All smoke tests passing | | |
| SSO login verified | | |
| No access keys in repo | | |
| Security review complete | | |
| Rollback procedure tested | | |

**Security Lead sign-off:** _______________ Date: _______________
**Platform Owner sign-off:** _______________ Date: _______________
