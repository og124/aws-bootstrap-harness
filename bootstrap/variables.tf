variable "region" {
  description = "Region for the state bucket. Keep every project's backend pointing here."
  type        = string
  default     = "eu-west-1"
}

variable "state_bucket_name" {
  description = "Globally unique name for the shared Terraform state bucket, e.g. \"<you>-tf-state\"."
  type        = string
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if one already exists in this account."
  type        = bool
  default     = true
}
