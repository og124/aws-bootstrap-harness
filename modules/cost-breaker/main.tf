# Cost circuit breaker for a CloudFront distribution.
#
# AWS has no hard billing cap. For a public site behind CloudFront the
# realistic way to run up a bill is request volume, so the hard stop is to
# disable the distribution:
#
#   CloudWatch: requests/hour > N  ─┐
#   CloudWatch: bytes/hour    > N  ─┼─> SNS "breaker" ──> Lambda ──> distribution Enabled = false
#   Budget: 100% of monthly limit  ─┘          └───────> SNS "alerts" ──> email
#
# Everything is in us-east-1: CloudFront publishes its metrics only there.
# The distribution must ignore changes to `enabled` (modules/static-site does),
# or the next apply quietly undoes a trip. Re-enabling is deliberate: invoke
# the function with {"action":"enable"} after looking at the traffic.

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.60"
      configuration_aliases = [aws.us_east_1]
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Topics: "breaker" acts, "alerts" tells a human.
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "breaker" {
  provider = aws.us_east_1
  name     = "${var.name}-breaker"
}

resource "aws_sns_topic" "alerts" {
  provider = aws.us_east_1
  name     = "${var.name}-alerts"
}

# Note: AWS emails a confirmation link on first apply. Until it's clicked the
# subscription is "PendingConfirmation", nothing is delivered, and it expires
# after three days. Click it.
resource "aws_sns_topic_subscription" "email" {
  provider  = aws.us_east_1
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

data "aws_iam_policy_document" "topic" {
  for_each = { breaker = aws_sns_topic.breaker.arn, alerts = aws_sns_topic.alerts.arn }

  statement {
    actions   = ["SNS:Publish"]
    resources = [each.value]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "budgets.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "topic" {
  provider = aws.us_east_1
  for_each = { breaker = aws_sns_topic.breaker.arn, alerts = aws_sns_topic.alerts.arn }
  arn      = each.value
  policy   = data.aws_iam_policy_document.topic[each.key].json
}

# ---------------------------------------------------------------------------
# Triggers
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "trip" {
  provider = aws.us_east_1
  for_each = {
    requests = { metric = "Requests", threshold = var.requests_per_hour, unit = "requests" }
    bytes    = { metric = "BytesDownloaded", threshold = var.bytes_per_hour, unit = "bytes" }
  }

  alarm_name          = "${var.name}-${each.key}-per-hour"
  alarm_description   = "More than ${each.value.threshold} ${each.value.unit} in an hour: trips the cost breaker."
  namespace           = "AWS/CloudFront"
  metric_name         = each.value.metric
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = each.value.threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { DistributionId = var.distribution_id, Region = "Global" }
  alarm_actions       = [aws_sns_topic.breaker.arn, aws_sns_topic.alerts.arn]
}

resource "aws_budgets_budget" "monthly" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Credits would otherwise hide real usage: a budget that subtracts them can
  # read $0.00 forever and never fire.
  cost_types {
    include_credit = false
    include_refund = false
  }

  # Scope to this project if its resources are tagged (and the tag key is
  # activated as a cost allocation tag in Billing). Otherwise the whole account.
  dynamic "cost_filter" {
    for_each = var.budget_tag == null ? [] : [var.budget_tag]
    content {
      name   = "TagKeyValue"
      values = ["user:${cost_filter.value.key}$${cost_filter.value.value}"]
    }
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.breaker.arn, aws_sns_topic.alerts.arn]
  }

  depends_on = [aws_sns_topic_policy.topic]
}

# ---------------------------------------------------------------------------
# The function that pulls the plug
# ---------------------------------------------------------------------------

data "archive_file" "breaker" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.mjs"
  output_path = "${path.module}/.build/${var.name}-breaker.zip"
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "breaker" {
  name               = "${var.name}-breaker"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "breaker" {
  statement {
    sid       = "ToggleOnlyThisDistribution"
    actions   = ["cloudfront:GetDistributionConfig", "cloudfront:UpdateDistribution"]
    resources = [var.distribution_arn]
  }

  statement {
    sid       = "Alert"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.breaker.arn}:*"]
  }
}

resource "aws_iam_role_policy" "breaker" {
  name   = "breaker"
  role   = aws_iam_role.breaker.id
  policy = data.aws_iam_policy_document.breaker.json
}

resource "aws_cloudwatch_log_group" "breaker" {
  provider          = aws.us_east_1
  name              = "/aws/lambda/${var.name}-breaker"
  retention_in_days = 30
}

resource "aws_lambda_function" "breaker" {
  provider         = aws.us_east_1
  function_name    = "${var.name}-breaker"
  role             = aws_iam_role.breaker.arn
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  filename         = data.archive_file.breaker.output_path
  source_code_hash = data.archive_file.breaker.output_base64sha256
  timeout          = 30
  memory_size      = 128

  # One at a time: a burst of alarms must not race UpdateDistribution calls
  # against each other's ETags.
  reserved_concurrent_executions = 1

  environment {
    variables = {
      DISTRIBUTION_ID = var.distribution_id
      ALERT_TOPIC_ARN = aws_sns_topic.alerts.arn
      NAME            = var.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.breaker, aws_iam_role_policy.breaker]
}

resource "aws_lambda_permission" "sns" {
  provider      = aws.us_east_1
  statement_id  = "AllowBreakerTopic"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.breaker.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.breaker.arn
}

resource "aws_sns_topic_subscription" "breaker" {
  provider   = aws.us_east_1
  topic_arn  = aws_sns_topic.breaker.arn
  protocol   = "lambda"
  endpoint   = aws_lambda_function.breaker.arn
  depends_on = [aws_lambda_permission.sns]
}
