# Bootstrap Steps -- Manual Console Actions

> **Status:** PENDING APPROVAL
> **Approvers required:** Security Lead + Platform Owner

All actions below are the ONLY permitted manual AWS console operations.

---

## Step 0 -- Run Inventory Export and Review Output

Before performing any manual console actions, run the inventory export script to capture the current state of the AWS account. Review the output and confirm there are no unexpected resources that would conflict with bootstrap.

```bash
bash scripts/inventory_export.sh --region us-west-2
```

Output is written to `scripts/inventory/<timestamp>/`. Review `scripts/inventory/<timestamp>/metadata.json` for a summary of discovered resources.

**Do not proceed to Step 1 until the inventory output has been reviewed and signed off.**

---

## Step 1 -- Create KMS Key for State Encryption

Console path: KMS > Customer managed keys > Create key

- Key type: Symmetric, Key usage: Encrypt and decrypt
- Alias: alias/terraform-state-bootstrap
- Region: us-west-2

Record the Key ARN: arn:aws:kms:us-west-2:ACCOUNT_ID:key/KEY_ID

---

## Step 2 -- Create Terraform State S3 Bucket

Console path: S3 > Create bucket

- Bucket name: ORGNAME-terraform-state-ACCOUNT_ID
- Region: us-west-2
- Block all public access: Enabled
- Bucket versioning: Enabled
- Default encryption: SSE-KMS (key from Step 1), Bucket key: Enabled
- Access logging: enabled, target bucket: ORGNAME-terraform-state-logs-ACCOUNT_ID

---

## Step 3 -- Create DynamoDB Lock Table

Console path: DynamoDB > Create table

- Table name: terraform-state-lock
- Partition key: LockID (String)
- Billing mode: PAY_PER_REQUEST
- Point-in-time recovery: Enabled

---

## Step 4 -- Create Bootstrap IAM Role

Console path: IAM > Roles > Create role

- Role name: TerraformBootstrapRole
- Trusted entity: AWS account (this account)
- Attach inline policy granting S3 + DynamoDB + KMS access to state resources only
- NOTE: Remove this role after GitHub OIDC deploy roles are operational

---

## Step 5 -- Register GitHub OIDC Provider

Console path: IAM > Identity providers > Add provider

- Provider type: OpenID Connect
- Provider URL: https://token.actions.githubusercontent.com
- Audience: sts.amazonaws.com

Record the Provider ARN: arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com

---

## Step 6 -- Enable IAM Identity Center

Console path: IAM Identity Center > Enable

- Enable in management account with AWS Organizations
- Record Instance ARN: arn:aws:sso:::instance/ssoins-XXXXXXXXXX
- Record Identity Store ID: d-XXXXXXXXXX

---

## Step 7 -- Update Backend Config in All Env Overlays

Update bucket, kms_key_id in envs/dev/main.tf, envs/staging/main.tf, envs/prod/main.tf

---

## Sign-off

| Step | Completed by | Date |
|------|-------------|------|
| 0 - Inventory review | | |
| 1 - KMS Key | | |
| 2 - S3 Bucket | | |
| 3 - DynamoDB | | |
| 4 - Bootstrap IAM Role | | |
| 5 - GitHub OIDC Provider | | |
| 6 - IAM Identity Center | | |
| 7 - Backend config updated | | |

Security Lead sign-off: _______________ Date: _______________
Platform Owner sign-off: _______________ Date: _______________
