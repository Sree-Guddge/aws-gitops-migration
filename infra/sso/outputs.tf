output "instance_arn" {
  description = "ARN of the IAM Identity Center instance"
  value       = module.sso.instance_arn
}

output "identity_store_id" {
  description = "Identity Store ID (used to look up SCIM-synced group IDs)"
  value       = module.sso.identity_store_id
}

output "permission_set_arns" {
  description = "Map of permission set name to ARN"
  value       = module.sso.permission_set_arns
}
output "managed_group_ids" {
  description = "Map of AWS-managed group display name to its Identity Store group ID"
  value       = { for k, g in module.sso.managed_group_ids : k => g }
}
