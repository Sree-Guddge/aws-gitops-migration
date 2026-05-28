# Non-sensitive values committed to source.
# Sensitive values (account_id, kms_admin_arns, billing_email) must be injected
# at runtime via -var flags or GitHub Actions secrets -- do NOT commit them here.
#
# Example init command:
#   terraform init \
#     -backend-config="bucket=<STATE_BUCKET_NAME>" \
#     -backend-config="kms_key_id=<KMS_KEY_ARN>"
#
# Example plan/apply command:
#   terraform apply \
#     -var="account_id=$PROD_ACCOUNT_ID" \
#     -var="kms_admin_arns=[\"$PLATFORM_ADMIN_ROLE_ARN\"]" \
#     -var="billing_email=$BILLING_EMAIL"

org_name = "myorg"

vpc_cidr             = "10.30.0.0/16"
public_subnet_cidrs  = ["10.30.0.0/24", "10.30.1.0/24", "10.30.2.0/24"]
private_subnet_cidrs = ["10.30.10.0/24", "10.30.11.0/24", "10.30.12.0/24"]
