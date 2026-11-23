variable "name" {
  description = "Prefix for the breaker's resources, e.g. \"example-site\"."
  type        = string
}

variable "distribution_id" {
  description = "The CloudFront distribution to protect (modules/static-site output distribution_id)."
  type        = string
}

variable "distribution_arn" {
  description = "Its ARN (modules/static-site output distribution_arn). The function can toggle nothing else."
  type        = string
}

variable "requests_per_hour" {
  description = "Trip above this many requests in an hour. Size it well above real peak traffic."
  type        = number
  default     = 100000
}

variable "bytes_per_hour" {
  description = "Trip above this many bytes served in an hour. Default 5 GiB."
  type        = number
  default     = 5368709120
}

variable "monthly_budget_usd" {
  description = "Monthly budget. 80% forecast emails you; 100% actual trips the breaker."
  type        = number
  default     = 10
}

variable "budget_tag" {
  description = "Scope the budget to resources tagged key=value (the key must be an activated cost allocation tag). null = whole account."
  type = object({
    key   = string
    value = string
  })
  default = null
}

variable "alert_email" {
  description = "Where trips, failures and budget warnings go. Confirm the subscription email AWS sends."
  type        = string
  default     = ""
}
