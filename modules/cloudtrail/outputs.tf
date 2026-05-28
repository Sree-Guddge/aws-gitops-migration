output "trail_arn" {
  value = aws_cloudtrail.this.arn
}

output "s3_bucket_id" {
  value = local.trail_bucket_id
}
