# Operational Runbook

## Day-to-Day Operations

### Making Infrastructure Changes

1. Create a feature branch from main
2. Make changes to Terraform code in envs/ or modules/
3. Push and open a PR
4. CI runs fmt/validate/plan and posts plan output to PR
5. Review plan output and request code review
6. Merge to main after approval
7. CD applies changes automatically (dev) or after manual approval (prod)

### Responding to Terraform Drift

If drift is detected (manual console changes):

1. Run terraform plan in the affected environment
2. Review the diff -- determine if drift is expected or unauthorized
3. If unauthorized: revert via terraform apply to restore desired state
4. If expected: import the resource or update Terraform to match
5. Document the incident and update controls to prevent recurrence

### Adding a New Environment

1. Copy envs/prod/ to envs/new-env/
2. Update backend key, variables, and tags
3. Create a new GitHub environment with appropriate reviewers
4. Add AWS_DEPLOY_ROLE_NEW_ENV secret
5. Create a new apply workflow in ci/apply-new-env.yml
6. Test with a non-critical resource first

### Rotating OIDC Roles

If a deploy role is compromised:

1. Revoke all active sessions: aws iam delete-role-policy --role-name github-deploy-prod --policy-name terraform-state-access
2. Update the trust policy to restrict to a specific commit SHA temporarily
3. Rotate any secrets the role had access to (Secrets Manager, KMS)
4. Restore the trust policy after verification
5. Audit CloudTrail for unauthorized actions

### Updating Terraform Version

1. Update TF_VERSION in all ci/*.yml workflows
2. Test locally: terraform init -upgrade && terraform plan
3. Commit and push to a feature branch
4. Verify CI passes before merging

---

## Incident Response

### Unauthorized AWS Console Change Detected

1. Identify the principal via CloudTrail (eventName, userIdentity)
2. If IAM user: disable access keys immediately
3. If federated user: revoke SSO session and review Entra ID logs
4. Run terraform plan to assess drift
5. Apply Terraform to restore desired state
6. Document in incident log and update IAM policies

### Terraform State Corruption

1. List S3 bucket versions: aws s3api list-object-versions --bucket STATE_BUCKET --prefix ENV/
2. Identify the last known good state version
3. Download: aws s3api get-object --bucket STATE_BUCKET --key ENV/terraform.tfstate --version-id VERSION_ID state-backup.tfstate
4. Restore: aws s3 cp state-backup.tfstate s3://STATE_BUCKET/ENV/terraform.tfstate
5. Verify: terraform plan (should show no changes if restore was correct)
6. Root cause analysis: check CloudTrail for unauthorized PutObject calls

### GitHub Actions Workflow Failure

1. Check workflow logs in GitHub Actions UI
2. Common causes:
   - OIDC assume role failure: verify trust policy and GitHub environment config
   - Terraform plan failure: review plan output for resource conflicts
   - State lock timeout: check DynamoDB for stale locks (LockID item)
3. To manually release a stale lock:
   ```bash
   aws dynamodb delete-item \
     --table-name terraform-state-lock \
     --key "{\"LockID\": {\"S\": \"STATE_BUCKET/ENV/terraform.tfstate-md5\"}}"
   ```

---

## Maintenance Windows

### Monthly Tasks

- Review IAM Access Analyzer findings
- Audit CloudTrail logs for anomalies
- Verify GuardDuty findings and remediate
- Review Terraform state bucket access logs
- Rotate SCIM token (if expiring)

### Quarterly Tasks

- Review and update permission sets
- Audit SSO group memberships in Entra ID
- Test rollback procedure in staging
- Review and update this runbook
