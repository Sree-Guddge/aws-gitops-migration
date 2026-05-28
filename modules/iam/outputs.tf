output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "deploy_role_arns" {
  description = "Map of environment to deploy role ARN"
  value       = { for k, v in aws_iam_role.deploy : k => v.arn }
}
