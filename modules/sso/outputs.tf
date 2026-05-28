output "instance_arn" {
  value = local.instance_arn
}

output "identity_store_id" {
  value = local.identity_store_id
}

output "permission_set_arns" {
  value = { for k, v in aws_ssoadmin_permission_set.this : k => v.arn }
}
