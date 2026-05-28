output "key_id" {
  value = local.key_id
}

output "key_arn" {
  value = local.key_arn
}

output "alias_arn" {
  value = aws_kms_alias.this.arn
}
