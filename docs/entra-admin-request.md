# Action Request: AWS IAM Identity Center -- Entra Group Provisioning

**To:** Entra ID / Azure AD administrator
**From:** Platform / AWS migration
**Priority:** Blocker for AWS SSO group-based access

## Context
SSO login from Entra to AWS IAM Identity Center is working -- the 6 `@guddge.com`
**users** sync correctly. However, the **groups** that drive AWS permission assignment
are NOT syncing. Only `Amazon Q User` and `kiro` appear in AWS; the required `aws-*`
groups are missing.

Root cause (most likely): the `aws-*` groups are **not assigned to the AWS IAM Identity
Center enterprise application** in Entra. SCIM only provisions users/groups that are
in the app's assignment scope. Assigning apps requires an elevated role that the
requester does not hold.

## What we need you to do

### 1. Ensure these groups exist in Entra ID
- `aws-admins`
- `aws-powerusers`
- `aws-readonly`
- `aws-billing`
- `aws-developers`

### 2. Assign the groups to the AWS enterprise app
- Entra admin center > Enterprise applications > **AWS IAM Identity Center** (the AWS SSO app)
- **Users and groups** > **Add user/group**
- Add all five `aws-*` groups
- (Required role: Application Administrator, or owner of this app)

### 3. Confirm SCIM provisioning scope and run it
- Same app > **Provisioning**
- Provisioning status: **On**
- Scope: **Sync only assigned users and groups**
- Click **Provision on demand** (or wait for the next cycle) and confirm the `aws-*`
  groups provision without errors

### 4. (When ready) Conditional Access / MFA
- Confirm a Conditional Access policy requires MFA for the AWS app, scoped to the `aws-*` groups
- (Required role: Conditional Access Administrator / Security Administrator)

## How we verify success (AWS side, we will run this)
```bash
aws identitystore list-groups --region us-east-1 \
  --identity-store-id d-90663e376f \
  --query "Groups[*].DisplayName" --output table
```
Success = the five `aws-*` groups appear in that list.

## Environment facts
- AWS account (management): 286684483345
- IAM Identity Center home region: us-east-1
- Identity Store ID: d-90663e376f
- SSO instance ARN: arn:aws:sso:::instance/ssoins-7223ba457995e15d