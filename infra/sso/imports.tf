# infra/sso/imports.tf
# Native Terraform import blocks adopting the IAM Identity Center permission sets
# that were created in the console, so they are managed as code with zero recreation.
# Import ID format for permission sets: <permission_set_arn>,<instance_arn>
# After a successful apply that shows these as imported (not created), this file
# can be kept for documentation or removed (import blocks are idempotent no-ops once in state).

import {
  to = module.sso.aws_ssoadmin_permission_set.this["AdministratorAccess"]
  id = "arn:aws:sso:::permissionSet/ssoins-7223ba457995e15d/ps-007a9d96b3f06bbb,arn:aws:sso:::instance/ssoins-7223ba457995e15d"
}

import {
  to = module.sso.aws_ssoadmin_permission_set.this["PowerUserAccess"]
  id = "arn:aws:sso:::permissionSet/ssoins-7223ba457995e15d/ps-72237a8a924dec33,arn:aws:sso:::instance/ssoins-7223ba457995e15d"
}

import {
  to = module.sso.aws_ssoadmin_permission_set.this["ReadOnly"]
  id = "arn:aws:sso:::permissionSet/ssoins-7223ba457995e15d/ps-72235e458ead9f03,arn:aws:sso:::instance/ssoins-7223ba457995e15d"
}

import {
  to = module.sso.aws_ssoadmin_permission_set.this["Billing"]
  id = "arn:aws:sso:::permissionSet/ssoins-7223ba457995e15d/ps-7223026c9bd6e7f9,arn:aws:sso:::instance/ssoins-7223ba457995e15d"
}

import {
  to = module.sso.aws_ssoadmin_permission_set.this["Developer"]
  id = "arn:aws:sso:::permissionSet/ssoins-7223ba457995e15d/ps-72237cd54a52136f,arn:aws:sso:::instance/ssoins-7223ba457995e15d"
}

import {
  to = module.sso.aws_ssoadmin_permission_set.this["RegionalAdmin"]
  id = "arn:aws:sso:::permissionSet/ssoins-7223ba457995e15d/ps-72235eac02b09572,arn:aws:sso:::instance/ssoins-7223ba457995e15d"
}


# --- Managed policy attachments (id: <managed_arn>,<permission_set_arn>,<instance_arn>) ---
import {
  to = module.sso.aws_ssoadmin_managed_policy_attachment.this["PowerUserAccess-arn:aws:iam::aws:policy/PowerUserAccess"]
  id = "arn:aws:iam::aws:policy/PowerUserAccess,arn:aws:sso:::permissionSet/ssoins-7223ba457995e15d/ps-72237a8a924dec33,arn:aws:sso:::instance/ssoins-7223ba457995e15d"
}

import {
  to = module.sso.aws_ssoadmin_managed_policy_attachment.this["ReadOnly-arn:aws:iam::aws:policy/ReadOnlyAccess"]
  id = "arn:aws:iam::aws:policy/ReadOnlyAccess,arn:aws:sso:::permissionSet/ssoins-7223ba457995e15d/ps-72235e458ead9f03,arn:aws:sso:::instance/ssoins-7223ba457995e15d"
}

import {
  to = module.sso.aws_ssoadmin_managed_policy_attachment.this["Billing-arn:aws:iam::aws:policy/job-function/Billing"]
  id = "arn:aws:iam::aws:policy/job-function/Billing,arn:aws:sso:::permissionSet/ssoins-7223ba457995e15d/ps-7223026c9bd6e7f9,arn:aws:sso:::instance/ssoins-7223ba457995e15d"
}

import {
  to = module.sso.aws_ssoadmin_managed_policy_attachment.this["Developer-arn:aws:iam::aws:policy/PowerUserAccess"]
  id = "arn:aws:iam::aws:policy/PowerUserAccess,arn:aws:sso:::permissionSet/ssoins-7223ba457995e15d/ps-72237cd54a52136f,arn:aws:sso:::instance/ssoins-7223ba457995e15d"
}

# --- Inline policies (id: <permission_set_arn>,<instance_arn>) ---
import {
  to = module.sso.aws_ssoadmin_permission_set_inline_policy.this["AdministratorAccess"]
  id = "arn:aws:sso:::permissionSet/ssoins-7223ba457995e15d/ps-007a9d96b3f06bbb,arn:aws:sso:::instance/ssoins-7223ba457995e15d"
}

import {
  to = module.sso.aws_ssoadmin_permission_set_inline_policy.this["RegionalAdmin"]
  id = "arn:aws:sso:::permissionSet/ssoins-7223ba457995e15d/ps-72235eac02b09572,arn:aws:sso:::instance/ssoins-7223ba457995e15d"
}

