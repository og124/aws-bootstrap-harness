output "function_name" {
  description = "Invoke with {\"action\":\"enable\"} (region us-east-1) to restore service after a trip."
  value       = aws_lambda_function.breaker.function_name
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
