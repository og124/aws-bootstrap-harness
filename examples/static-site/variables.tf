variable "name" {
  type    = string
  default = "example-site"
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "domain_name" {
  description = "e.g. example.com"
  type        = string
}

variable "zone_name" {
  description = "Existing Route 53 hosted zone, e.g. example.com"
  type        = string
}

variable "github_repository" {
  description = "owner/name of the repo this site deploys from"
  type        = string
}

variable "oidc_provider_arn" {
  description = "bootstrap/ output"
  type        = string
}

variable "state_bucket" {
  description = "bootstrap/ output"
  type        = string
}

variable "alert_email" {
  type    = string
  default = ""
}
