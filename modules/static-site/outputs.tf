output "bucket_name" {
  description = "Sync the built site here."
  value       = aws_s3_bucket.site.id
}

output "bucket_arn" {
  value = aws_s3_bucket.site.arn
}

output "distribution_id" {
  description = "Invalidate after every sync; also what the cost breaker disables."
  value       = aws_cloudfront_distribution.site.id
}

output "distribution_arn" {
  value = aws_cloudfront_distribution.site.arn
}

output "url" {
  value = "https://${var.domain_name}"
}
