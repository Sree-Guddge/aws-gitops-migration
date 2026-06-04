output "instance_arn" {
  value = local.instance_arn
}

output "identity_store_id" {
  value = local.identity_store_id
}

output "permission_set_arns" {
  value = { for k, v in aws_ssoadmin_permission_set.this : k => v.arn }
}

output "managed_group_ids" {
  description = "Map of AWS-managed group display name to Identity Store group ID"
  value       = { for k, g in aws_identitystore_group.managed : k => g.group_id }
}
