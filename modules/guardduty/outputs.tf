output "detector_id" {
  description = "The GuardDuty detector ID"
  value       = aws_guardduty_detector.this.id
}

output "findings_bucket_id" {
  description = "The name (ID) of the GuardDuty findings S3 bucket"
  value       = aws_s3_bucket.findings.id
}

output "findings_bucket_arn" {
  description = "The ARN of the GuardDuty findings S3 bucket"
  value       = aws_s3_bucket.findings.arn
}
