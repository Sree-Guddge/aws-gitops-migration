# Admin Handover Runbook (final step)

**Goal:** Make `mamtaj@guddge.com` and `bhanua@guddge.com` the AWS admins; remove
`sreevatsav@guddge.com` from admin. Execute ONLY after the rest of the SSO migration
is verified working.

## Preconditions
- [ ] `mamtaj@guddge.com` assigned to the AWS IAM Identity Center app in Entra (admin task)
      and synced into the Identity Store. Verify:
      `aws identitystore list-users --region us-east-1 --identity-store-id d-90663e376f --query "Users[?UserName=='mamtaj@guddge.com']" --output text`
- [ ] `bhanua@guddge.com` present (already synced).
- [ ] PR #3 applied so `AdministratorAccess` has the real managed policy.

## Step 1 -- add the new admins (additive, low risk)
In `infra/sso/terraform.tfvars`:
```hcl
managed_groups = {
  "aws-admins" = ["sreevatsav@guddge.com", "mamtaj@guddge.com", "bhanua@guddge.com"]
}
managed_group_assignments = [
  { group_name = "aws-admins", account_id = "286684483345", permission_set = "AdministratorAccess" },
]
```
`terraform apply`. Keep sreevatsav in the list for now.

## Step 2 -- VERIFY before removing anyone
- [ ] mamtaj logs in via the AWS access portal, assumes AdministratorAccess, confirms console works.
- [ ] bhanua does the same.
Do NOT proceed until both are confirmed.

## Step 3 -- remove the outgoing admin
In `infra/sso/terraform.tfvars`, drop sreevatsav:
```hcl
managed_groups = {
  "aws-admins" = ["mamtaj@guddge.com", "bhanua@guddge.com"]
}
```
`terraform apply`.

## Step 4 -- break-glass safety (do NOT skip)
- Keep an independent break-glass path until SSO admin is fully proven:
  the IAM user `n8n-user` and/or account root with MFA. These are NOT SSO-dependent.
- Decommission `n8n-user` and remaining direct IAM users only as the very last action,
  after multiple successful SSO admin logins.

## Rollback
If the new admins cannot log in: re-add sreevatsav to `aws-admins` and `terraform apply`,
or use the break-glass IAM user / root to restore access.