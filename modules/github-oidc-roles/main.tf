# Two roles per repository, assumable only by that repository's GitHub Actions
# workflows — no long-lived AWS keys anywhere:
#
#   <name>-plan    read-only; pull requests (to post a `terraform plan`)
#   <name>-apply   read/write; pushes to the deploy branch only
#
# Both can read and write *only their own* state key and its lockfile.
#
# GitHub may present the OIDC subject in its plain form
# (repo:owner/name:...) or, for repositories with immutable-ID claims enabled,
# an ID-qualified form (repo:owner@<id>/name@<id>:...). Both are accepted when
# the IDs are supplied, so a repo setting change can't lock deploys out.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  owner = split("/", var.github_repository)[0]
  repo  = split("/", var.github_repository)[1]

  qualified = var.github_owner_id != "" && var.github_repo_id != "" ? "${local.owner}@${var.github_owner_id}/${local.repo}@${var.github_repo_id}" : ""

  plan_subjects = compact([
    "repo:${var.github_repository}:pull_request",
    local.qualified != "" ? "repo:${local.qualified}:pull_request" : "",
  ])

  apply_subjects = compact([
    "repo:${var.github_repository}:ref:refs/heads/${var.deploy_branch}",
    local.qualified != "" ? "repo:${local.qualified}:ref:refs/heads/${var.deploy_branch}" : "",
  ])
}

data "aws_iam_policy_document" "trust" {
  for_each = { plan = local.plan_subjects, apply = local.apply_subjects }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "${var.name}-plan"
  description          = "Terraform plan for ${var.github_repository} pull requests (read-only)"
  assume_role_policy   = data.aws_iam_policy_document.trust["plan"].json
  max_session_duration = 3600
}

resource "aws_iam_role" "apply" {
  name                 = "${var.name}-apply"
  description          = "Terraform apply + deploy for ${var.github_repository} on ${var.deploy_branch}"
  assume_role_policy   = data.aws_iam_policy_document.trust["apply"].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# State access: this project's key and its S3-native lockfile, nothing else.
data "aws_iam_policy_document" "state" {
  statement {
    sid       = "ListOwnPrefix"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.state_key}*"]
    }
  }

  statement {
    sid       = "ReadWriteOwnStateAndLock"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/${var.state_key}", "arn:aws:s3:::${var.state_bucket}/${var.state_key}.tflock"]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "terraform-state"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.state.json
}

resource "aws_iam_role_policy" "apply_state" {
  name   = "terraform-state"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.state.json
}

# What the deploy may change. Scope this to the services the project actually
# manages — and, where the service supports it, to the project's resources by
# name or tag. A broad `service:*` on `*` lets a compromised workflow touch
# every other project in the account.
resource "aws_iam_role_policy" "apply" {
  name   = "deploy"
  role   = aws_iam_role.apply.id
  policy = var.apply_policy_json
}
