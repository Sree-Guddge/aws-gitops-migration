# Entra ID SSO + SCIM Configuration Guide

## Overview

This guide covers configuring Microsoft Entra ID as the identity provider for AWS IAM Identity Center using SAML 2.0 and SCIM provisioning.

---

## Part 1 -- SAML Configuration

### 1.1 Create Enterprise Application in Entra ID

1. Sign in to Entra ID admin center (https://entra.microsoft.com)
2. Navigate to: Enterprise applications > New application
3. Search for "AWS IAM Identity Center" in the gallery
4. Click "Create"

### 1.2 Configure SAML SSO

1. Open the new app > Single sign-on > SAML
2. Download the Federation Metadata XML from Entra ID
3. In AWS IAM Identity Center console:
   - Settings > Identity source > Change identity source
   - Select "External identity provider"
   - Upload the Entra ID Federation Metadata XML
   - Download the AWS IAM Identity Center SAML metadata
4. Back in Entra ID, upload the AWS SAML metadata:
   - Identifier (Entity ID): from AWS metadata
   - Reply URL (ACS URL): from AWS metadata

### 1.3 Configure SAML Attributes

In Entra ID SAML attribute mappings, configure:

| Claim name | Value |
|-----------|-------|
| Subject (NameID) | user.userprincipalname |
| https://aws.amazon.com/SAML/Attributes/Role | (mapped via SCIM groups) |
| https://aws.amazon.com/SAML/Attributes/RoleSessionName | user.userprincipalname |
| https://aws.amazon.com/SAML/Attributes/SessionDuration | 28800 |

### 1.4 Assign Users and Groups

1. In Entra ID app > Users and groups > Add user/group
2. Assign the following groups (create if they do not exist):
   - aws-admins
   - aws-powerusers
   - aws-readonly
   - aws-billing
   - aws-developers

---

## Part 2 -- SCIM Provisioning

### 2.1 Enable SCIM in AWS IAM Identity Center

1. AWS IAM Identity Center > Settings > Automatic provisioning
2. Click "Enable"
3. Copy the SCIM endpoint URL and access token
4. Store the access token in AWS Secrets Manager:
   - Secret name: /sso/scim-token
   - Value: the token from IAM Identity Center

### 2.2 Configure SCIM in Entra ID

1. In Entra ID app > Provisioning > Get started
2. Provisioning mode: Automatic
3. Tenant URL: paste the SCIM endpoint from AWS
4. Secret token: paste the access token from AWS
5. Click "Test Connection" -- must succeed before saving
6. Save

### 2.3 Configure Attribute Mappings

Ensure the following Entra ID attributes map to SCIM:

| Entra ID attribute | SCIM attribute |
|-------------------|----------------|
| userPrincipalName | userName |
| displayName | displayName |
| givenName | name.givenName |
| surname | name.familyName |
| mail | emails[type eq "work"].value |

### 2.4 Set Provisioning Scope

1. Provisioning > Settings > Scope
2. Select "Sync only assigned users and groups"
3. Assign the aws-* groups to the application

### 2.5 Start Provisioning

1. Click "Start provisioning"
2. Monitor the provisioning logs for errors
3. Verify groups and users appear in AWS IAM Identity Center > Groups

---

## Part 3 -- Permission Set to Group Mapping (Terraform)

Permission sets and group-to-account assignments are managed by the deployable
`infra/sso/` Terraform root (which wraps `modules/sso`). The five permission sets
(AdministratorAccess, PowerUserAccess, ReadOnly, Billing, Developer, RegionalAdmin) are created from the module default.

After SCIM sync, get the Identity Store Group IDs:
```bash
aws identitystore list-groups \
  --identity-store-id d-XXXXXXXXXX \
  --query "Groups[*].{GroupId:GroupId,DisplayName:DisplayName}" \
  --output table
```

Copy `infra/sso/terraform.tfvars.example` to `infra/sso/terraform.tfvars` and fill in
the synced group IDs:
```hcl
account_assignments = [
  {
    group_id       = "IDENTITY_STORE_GROUP_ID_FOR_aws-admins"
    account_id     = "PROD_ACCOUNT_ID"
    permission_set = "Admin"
  },
  {
    group_id       = "IDENTITY_STORE_GROUP_ID_FOR_aws-developers"
    account_id     = "PROD_ACCOUNT_ID"
    permission_set = "Developer"
  },
  # Add more mappings as needed
]
```

Then apply (from the management account where IAM Identity Center is enabled):
```bash
cd infra/sso
terraform init
terraform plan
terraform apply
```

Validate the result with the prod smoke test, which checks that all five permission
sets exist:
```bash
bash tests/smoke_prod.sh
```

---

## Part 4 -- MFA and Conditional Access

Configure in Entra ID > Enterprise applications > [AWS app] > Conditional Access:

1. Create a new Conditional Access policy:
   - Name: "Require MFA for AWS access"
   - Users: aws-* groups
   - Cloud apps: AWS IAM Identity Center app
   - Grant: Require multi-factor authentication
   - Session: Sign-in frequency: 8 hours

2. Optionally add location-based conditions (e.g., block non-corporate IPs)

---

## Verification

1. Sign in as a non-admin Entra user assigned to aws-developers group
2. Navigate to: https://d-XXXXXXXXXX.awsapps.com/start
3. Verify MFA prompt appears
4. Verify the correct AWS accounts and permission sets are visible
5. Assume the Developer role and verify access is scoped correctly
