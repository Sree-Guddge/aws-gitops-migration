# Rollback Plan: AWS GitOps Migration

> This document defines the rollback procedures for each phase of the AWS GitOps migration from eu-west-2 to us-west-2.
> Each phase has a defined Recovery Time Objective (RTO) and step-by-step reversal procedure.

---

## Phase 1: Bootstrap Rollback

**RTO: 30 minutes**

**Trigger:** Bootstrap module apply fails, state bucket is misconfigured, or OIDC provider is incorrectly configured.

### Procedure

1. **Verify failure scope** - Determine which bootstrap resources were created vs. failed:
   ```bash
   aws s3api head-bucket --bucket <org>-terraform-state-<account-id> --region us-west-2
   aws dynamodb describe-table --table-name terraform-state-lock --region us-west-2
   aws iam list-open-id-connect-providers
   ```

2. **Remove OIDC provider** (if incorrectly configured):
   ```bash
   aws iam delete-open-id-connect-provider \
     --open-id-connect-provider-arn arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com
   ```

3. **Delete DynamoDB lock table** (if empty / no active locks):
   ```bash
   aws dynamodb delete-table --table-name terraform-state-lock --region us-west-2
   ```

4. **Empty and delete state S3 bucket** (only if no valid state exists):
   ```bash
   aws s3 rm s3://<org>-terraform-state-<account-id> --recursive --region us-west-2
   aws s3api delete-bucket --bucket <org>-terraform-state-<account-id> --region us-west-2
   ```

5. **Schedule KMS key deletion** (if bootstrap KMS key was created):
   ```bash
   aws kms schedule-key-deletion \
     --key-id <bootstrap-kms-key-id> \
     --pending-window-in-days 7 \
     --region us-west-2
   ```

6. **Re-enable temporary bootstrap IAM role** if it was already decommissioned:
   ```bash
   aws iam attach-role-policy \
     --role-name TerraformBootstrapRole \
     --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
   ```

### Verification

- [ ] No Terraform state bucket exists in us-west-2 (or bucket is empty)
- [ ] No DynamoDB lock table exists (or table has no lock entries)
- [ ] OIDC provider removed or correctly reconfigured
- [ ] Bootstrap IAM role is active and usable for retry

---

## Phase 2: State Import Rollback

**RTO: 1 hour**

**Trigger:** Resources were incorrectly imported into Terraform state, causing plan drift, unexpected changes, or state corruption.

### Procedure

1. **Identify incorrectly imported resources** - Review the Terraform plan output for unexpected changes:
   ```bash
   terraform plan -no-color 2>&1 | grep -E "(must be replaced|will be destroyed)"
   ```

2. **Remove specific resources from state** (does NOT destroy the actual AWS resource):
   ```bash
   # Remove a single resource
   terraform state rm module.vpc.aws_vpc.this

   # Remove an entire module
   terraform state rm module.vpc

   # Remove multiple resources
   terraform state rm module.cloudtrail.aws_cloudtrail.main
   terraform state rm module.guardduty.aws_guardduty_detector.main
   ```

3. **Verify state consistency** after removal:
   ```bash
   terraform plan -detailed-exitcode
   # Exit code 0 = no changes (clean state)
   # Exit code 2 = changes detected (review before proceeding)
   ```

4. **Restore state from backup** (if state is corrupted beyond repair):
   ```bash
   # List available state versions (S3 versioning)
   aws s3api list-object-versions \
     --bucket <org>-terraform-state-<account-id> \
     --prefix dev/terraform.tfstate \
     --region us-west-2

   # Restore a specific version
   aws s3api copy-object \
     --bucket <org>-terraform-state-<account-id> \
     --copy-source <org>-terraform-state-<account-id>/dev/terraform.tfstate?versionId=<version-id> \
     --key dev/terraform.tfstate \
     --region us-west-2
   ```

5. **Release DynamoDB lock** (if state operation left a stale lock):
   ```bash
   terraform force-unlock <lock-id>
   ```

### Verification

- [ ] `terraform plan` shows no unexpected destroy or replace operations
- [ ] All AWS resources remain running and unaffected
- [ ] State file version in S3 is consistent and not corrupted
- [ ] No stale locks in DynamoDB table

---

## Phase 3: Region Migration Rollback

**RTO: 2-4 hours** (depending on data volume of stateful resources)

**Trigger:** Resources in us-west-2 are not functioning correctly, data migration failed, or application connectivity issues after region cutover.

### Procedure

#### 3a. Revert Terraform Provider Region

1. **Update region variable** back to eu-west-2:
   ```bash
   # In each environment's terraform.tfvars or via CLI
   terraform apply -var="aws_region=eu-west-2"
   ```

2. **Revert backend configuration** (if state was migrated):
   ```bash
   terraform init -reconfigure \
     -backend-config="region=eu-west-2" \
     -backend-config="bucket=<org>-terraform-state-<account-id>"
   ```

#### 3b. Stateful Resource Restoration

**RDS (snapshot-and-restore):**
```bash
# Identify the pre-migration snapshot
aws rds describe-db-snapshots \
  --db-instance-identifier <db-name> \
  --query "DBSnapshots[?contains(DBSnapshotIdentifier, 'pre-migration')]" \
  --region eu-west-2

# Restore from pre-migration snapshot in eu-west-2
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier <db-name>-restored \
  --db-snapshot-identifier <pre-migration-snapshot-id> \
  --db-subnet-group-name <original-subnet-group> \
  --region eu-west-2

# Update application connection strings to point to restored instance
```

**ElastiCache (snapshot-and-restore):**
```bash
# Identify the pre-migration backup
aws elasticache describe-snapshots \
  --cache-cluster-id <cluster-name> \
  --region eu-west-2

# Create new cluster from backup
aws elasticache create-replication-group \
  --replication-group-id <cluster-name>-restored \
  --replication-group-description "Restored from pre-migration backup" \
  --snapshot-name <pre-migration-snapshot-name> \
  --region eu-west-2
```

**EFS (replication rollback):**
```bash
# If EFS replication was configured, promote the eu-west-2 source back
# Stop writes to us-west-2 replica
# Verify eu-west-2 source has latest data
# Update mount targets to point back to eu-west-2 file system
aws efs describe-mount-targets \
  --file-system-id <original-fs-id> \
  --region eu-west-2
```

**DynamoDB (Global Table rollback):**
```bash
# Remove us-west-2 replica from Global Table
aws dynamodb update-table \
  --table-name <table-name> \
  --replica-updates "Delete={RegionName=us-west-2}" \
  --region eu-west-2

# Verify eu-west-2 table is healthy
aws dynamodb describe-table --table-name <table-name> --region eu-west-2
```

**S3 (CRR rollback):**
```bash
# Disable cross-region replication
aws s3api delete-bucket-replication \
  --bucket <source-bucket-eu-west-2>

# Verify eu-west-2 bucket has all objects
aws s3 ls s3://<source-bucket-eu-west-2> --summarize --region eu-west-2
```

#### 3c. DNS Cutover Reversal

```bash
# Update Route 53 records to point back to eu-west-2 endpoints
aws route53 change-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "<service-domain>",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "<eu-west-2-alb-zone-id>",
          "DNSName": "<eu-west-2-alb-dns>",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'
```

### Verification

- [ ] All services responding on eu-west-2 endpoints
- [ ] Database connections restored and queries succeeding
- [ ] Application health checks passing
- [ ] No data loss confirmed (row counts, object counts match pre-migration baseline)
- [ ] Monitoring dashboards showing normal metrics in eu-west-2

---

## Phase 4: OIDC Cutover Rollback

**RTO: 15 minutes**

**Trigger:** GitHub Actions cannot authenticate to AWS via OIDC after the OIDC provider or deploy roles are modified.

### Procedure

1. **Re-enable temporary bootstrap IAM role** with static credentials:
   ```bash
   # Reactivate the TerraformBootstrapRole
   aws iam attach-role-policy \
     --role-name TerraformBootstrapRole \
     --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

   # Create temporary access key (store securely, rotate within 24h)
   aws iam create-access-key --user-name terraform-emergency-user
   ```

2. **Update GitHub Actions secrets** to use static credentials temporarily:
   - Set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in repository secrets
   - Modify workflow to use static credentials instead of OIDC:
   ```yaml
   # Temporary: replace OIDC step with static credentials
   - name: Configure AWS Credentials
     uses: aws-actions/configure-aws-credentials@v4
     with:
       aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
       aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
       aws-region: us-west-2
   ```

3. **Diagnose OIDC failure**:
   ```bash
   # Check OIDC provider exists and has correct thumbprint
   aws iam get-open-id-connect-provider \
     --open-id-connect-provider-arn arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com

   # Verify deploy role trust policy
   aws iam get-role --role-name github-deploy-dev \
     --query "Role.AssumeRolePolicyDocument"

   # Check CloudTrail for AssumeRoleWithWebIdentity failures
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
     --region us-west-2
   ```

4. **Fix OIDC configuration** (common issues):
   - Thumbprint mismatch: Update thumbprint list in bootstrap module
   - Sub condition mismatch: Verify GitHub repo/branch/environment in trust policy
   - Audience mismatch: Ensure `sts.amazonaws.com` is in client ID list
   - Session duration: Increase `max_session_duration` on the deploy role

5. **Restore OIDC authentication** once fixed:
   - Remove static credentials from GitHub secrets
   - Revert workflow to OIDC authentication
   - Deactivate/delete temporary access keys
   - Remove AdministratorAccess from bootstrap role

### Verification

- [ ] GitHub Actions workflow successfully assumes deploy role via OIDC
- [ ] No static AWS credentials remain in GitHub secrets
- [ ] TerraformBootstrapRole is deactivated or has minimal permissions
- [ ] CloudTrail shows successful AssumeRoleWithWebIdentity events

---

## Verification Checklist (Post-Rollback)

After completing any rollback phase, verify the following:

### Service Health

- [ ] All application endpoints responding (HTTP 200 on health checks)
- [ ] Database connections established and queries returning expected results
- [ ] Cache hit rates returning to normal levels
- [ ] Background job queues processing without errors
- [ ] No elevated error rates in application logs

### Infrastructure State

- [ ] Terraform state file is consistent (`terraform plan` shows expected state)
- [ ] No stale DynamoDB locks present
- [ ] S3 state bucket versioning shows clean history (no corruption)
- [ ] All resources tagged correctly with `ManagedBy = terraform`

### Security and Compliance

- [ ] CloudTrail showing expected API calls (no unauthorized activity during rollback)
- [ ] GuardDuty showing no new HIGH/CRITICAL findings related to rollback
- [ ] No temporary credentials or elevated permissions left active
- [ ] KMS keys in correct state (not pending deletion unless intended)
- [ ] All S3 buckets still have public access blocked

### Monitoring and Alerting

- [ ] CloudWatch alarms in OK state
- [ ] No unresolved incidents in alerting system
- [ ] Metrics dashboards showing normal patterns
- [ ] Log aggregation pipeline functioning

### Communication

- [ ] Stakeholders notified of rollback completion
- [ ] Incident report drafted (if applicable)
- [ ] Post-mortem scheduled (if rollback was due to failure)
- [ ] Next steps documented and assigned
