# modules/sso/main.tf
# Configures AWS IAM Identity Center permission sets and account assignments.
# The SSO instance must be enabled manually (bootstrap step 5) before applying.
# Entra ID SAML and SCIM are configured externally -- see docs/sso-setup.md.

data "aws_ssoadmin_instances" "this" {}

locals {
  instance_arn      = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
}

# Permission Sets
resource "aws_ssoadmin_permission_set" "this" {
  for_each = var.permission_sets

  name             = each.key
  description      = each.value.description
  instance_arn     = local.instance_arn
  session_duration = each.value.session_duration
  relay_state      = lookup(each.value, "relay_state", null)

  tags = var.tags
}

# Attach AWS managed policies to permission sets
resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = {
    for item in flatten([
      for ps_name, ps in var.permission_sets : [
        for policy_arn in ps.managed_policy_arns : {
          key        = "${ps_name}-${policy_arn}"
          ps_name    = ps_name
          policy_arn = policy_arn
        }
      ]
    ]) : item.key => item
  }

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.ps_name].arn
  managed_policy_arn = each.value.policy_arn
}

# Inline policies for permission sets
resource "aws_ssoadmin_permission_set_inline_policy" "this" {
  for_each = {
    for k, v in var.permission_sets : k => v
    if lookup(v, "inline_policy", null) != null
  }

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn
  inline_policy      = each.value.inline_policy
}

# Account assignments (group -> account -> permission set)
resource "aws_ssoadmin_account_assignment" "this" {
  for_each = {
    for item in var.account_assignments : "${item.group_id}-${item.account_id}-${item.permission_set}" => item
  }

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  principal_id       = each.value.group_id
  principal_type     = "GROUP"
  target_id          = each.value.account_id
  target_type        = "AWS_ACCOUNT"
}
