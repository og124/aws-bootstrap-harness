output "oidc_provider_arn" {
  description = "Pass to modules/github-oidc-roles as oidc_provider_arn."
  value       = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

output "state_bucket" {
  description = "Use as the S3 backend bucket in every project."
  value       = aws_s3_bucket.state.id
}

output "region" {
  value = var.region
}
