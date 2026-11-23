variable "name" {
  description = "Short, unique name for this site's resources, e.g. \"example-site\"."
  type        = string
}

variable "domain_name" {
  description = "The site's hostname, e.g. \"example.com\" or \"app.example.com\"."
  type        = string
}

variable "zone_name" {
  description = "Existing Route 53 public hosted zone the records go in, e.g. \"example.com\"."
  type        = string
}

variable "include_www" {
  description = "Also serve www.<domain_name>, 301'd to the apex by the viewer-request function."
  type        = bool
  default     = false
}

variable "content_security_policy" {
  description = "The Content-Security-Policy header. The default allows nothing but same-origin assets and no inline script or style."
  type        = string
  default     = "default-src 'none'; img-src 'self' data:; style-src 'self'; script-src 'self'; font-src 'self'; connect-src 'self'; manifest-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
}

variable "not_found_page" {
  description = "Path served, with status 404, for missing objects."
  type        = string
  default     = "/404.html"
}

variable "price_class" {
  description = "CloudFront price class. PriceClass_100 (North America + Europe edges) is cheapest per request."
  type        = string
  default     = "PriceClass_100"
}

variable "geo_restriction" {
  description = "mode = \"none\", \"blacklist\" (block the listed ISO 3166-1 alpha-2 countries) or \"whitelist\" (allow only them)."
  type = object({
    mode      = string
    countries = list(string)
  })
  default = { mode = "none", countries = [] }

  validation {
    condition     = contains(["none", "blacklist", "whitelist"], var.geo_restriction.mode)
    error_message = "geo_restriction.mode must be none, blacklist or whitelist."
  }
}
