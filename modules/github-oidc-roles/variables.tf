variable "name" {
  description = "Prefix for the two roles, e.g. \"example-site\" -> example-site-plan / example-site-apply."
  type        = string
}

variable "github_repository" {
  description = "owner/name of the repository whose workflows may assume the roles."
  type        = string

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repository))
    error_message = "github_repository must be owner/name."
  }
}

variable "github_owner_id" {
  description = "Numeric GitHub ID of the owner (gh api users/<owner> --jq .id). Optional; enables the ID-qualified OIDC subject."
  type        = string
  default     = ""
}

variable "github_repo_id" {
  description = "Numeric GitHub ID of the repository (gh api repos/<owner>/<name> --jq .id). Optional, as above."
  type        = string
  default     = ""
}

variable "deploy_branch" {
  description = "The only branch whose workflows may assume the apply role."
  type        = string
  default     = "main"
}

variable "oidc_provider_arn" {
  description = "From bootstrap/ output oidc_provider_arn."
  type        = string
}

variable "state_bucket" {
  description = "From bootstrap/ output state_bucket."
  type        = string
}

variable "state_key" {
  description = "This project's state object key, e.g. \"example-site/terraform.tfstate\". Must match its backend."
  type        = string
}

variable "apply_policy_json" {
  description = "IAM policy document (JSON) for what the deploy may change. Keep it to this project's services and resources."
  type        = string
}
