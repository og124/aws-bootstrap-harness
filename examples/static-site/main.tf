# A complete static site from the harness: hosting, a cost breaker, and the
# CI roles. Copy this directory into a new repo, set the variables, and see
# the top-level README for the order of first-time steps.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Partial backend: bucket and region are passed at init time
  #   terraform init -backend-config=bucket=<state bucket> -backend-config=region=<region>
  # so nothing account-specific is committed. use_lockfile = S3-native locking.
  backend "s3" {
    key          = "example-site/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}

data "aws_caller_identity" "current" {}

locals {
  tags = { project = var.name, "managed-by" = "terraform" }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = local.tags
  }
}

# CloudFront certificates and metrics live in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = local.tags
  }
}

module "site" {
  source    = "../../modules/static-site"
  providers = { aws = aws, aws.us_east_1 = aws.us_east_1 }

  name        = var.name
  domain_name = var.domain_name
  zone_name   = var.zone_name
  include_www = true
}

module "breaker" {
  source    = "../../modules/cost-breaker"
  providers = { aws = aws, aws.us_east_1 = aws.us_east_1 }

  name               = var.name
  distribution_id    = module.site.distribution_id
  distribution_arn   = module.site.distribution_arn
  monthly_budget_usd = 5
  budget_tag         = { key = "project", value = var.name }
  alert_email        = var.alert_email
}

# What the deploy workflow may touch: this site's bucket and distribution, its
# DNS zone, its certificate, and the resource types the modules manage. Scoped
# to this project wherever the service allows it.
data "aws_iam_policy_document" "deploy" {
  statement {
    sid       = "SyncThisSite"
    actions   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [module.site.bucket_arn, "${module.site.bucket_arn}/*"]
  }

  statement {
    sid       = "InvalidateThisSite"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
    resources = [module.site.distribution_arn]
  }

  # Terraform managing the stack. Scoped to resources named after this
  # project wherever AWS supports resource-level permissions; CloudFront, ACM,
  # Route 53 and Budgets largely don't at create time, so those stay broad.
  statement {
    sid = "ProjectNamedResources"
    actions = [
      "s3:*", "lambda:*", "logs:*", "sns:*", "cloudwatch:*",
      "iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole", "iam:TagRole", "iam:UntagRole",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:PassRole", "iam:ListInstanceProfilesForRole",
    ]
    resources = [
      "arn:aws:s3:::${var.name}-*",
      "arn:aws:lambda:*:${data.aws_caller_identity.current.account_id}:function:${var.name}-*",
      "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name}-*",
      "arn:aws:sns:*:${data.aws_caller_identity.current.account_id}:${var.name}-*",
      "arn:aws:cloudwatch:*:${data.aws_caller_identity.current.account_id}:alarm:${var.name}-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.name}-*",
    ]
  }

  statement {
    sid = "ServicesWithoutResourceScoping"
    actions = [
      "cloudfront:*", "acm:*", "route53:*", "budgets:*",
      "s3:ListAllMyBuckets", "lambda:List*", "logs:Describe*", "sns:ListTopics",
      "cloudwatch:Describe*", "iam:GetOpenIDConnectProvider", "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }
}

module "ci" {
  source = "../../modules/github-oidc-roles"

  name              = var.name
  github_repository = var.github_repository
  oidc_provider_arn = var.oidc_provider_arn
  state_bucket      = var.state_bucket
  state_key         = "example-site/terraform.tfstate"
  apply_policy_json = data.aws_iam_policy_document.deploy.json
}
