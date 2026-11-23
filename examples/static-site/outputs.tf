output "url" { value = module.site.url }
output "bucket_name" { value = module.site.bucket_name }
output "distribution_id" { value = module.site.distribution_id }
output "plan_role_arn" { value = module.ci.plan_role_arn }
output "apply_role_arn" { value = module.ci.apply_role_arn }
output "breaker_function" { value = module.breaker.function_name }
