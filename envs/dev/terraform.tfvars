# envs/dev/terraform.tfvars
# Non-sensitive values only. Secrets go in GitHub Secrets or AWS Secrets Manager.
#
# SENSITIVE VALUES - DO NOT COMMIT:
#   account_id    : inject at runtime via -var="account_id=123456789012"
#                   or via GitHub Actions secret: -var="account_id=${{ secrets.DEV_ACCOUNT_ID }}"
#   kms_admin_arns: inject at runtime via -var='kms_admin_arns=["arn:aws:iam::ACCOUNT_ID:role/PlatformAdminRole"]'
#                   or retrieve the ARN from SSM: aws ssm get-parameter --name /dev/platform-admin-role-arn

org_name = "myorg"

vpc_cidr             = "10.10.0.0/16"
public_subnet_cidrs  = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
private_subnet_cidrs = ["10.10.10.0/24", "10.10.11.0/24", "10.10.12.0/24"]