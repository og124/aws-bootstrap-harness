output "plan_role_arn" {
  description = "Set as the PLAN_ROLE_ARN repository variable."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Set as the APPLY_ROLE_ARN repository variable."
  value       = aws_iam_role.apply.arn
}
