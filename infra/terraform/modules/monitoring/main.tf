resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/cev/lambda"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "fargate_logs" {
  name              = "/cev/fargate"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "sfn_logs" {
  name              = "/cev/stepfunctions"
  retention_in_days = 30
}

resource "aws_sns_topic" "alerts" {
  name = "cev-alerts"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "sqs_depth" {
  alarm_name          = "cev-sqs-queue-depth-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 10
  alarm_description   = "SQS queue depth is high — Fargate may not be consuming fast enough"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = var.sqs_queue_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "cev-lambda-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Lambda error count exceeded threshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = var.orchestrator_lambda_name
  }
}

resource "aws_cloudwatch_metric_alarm" "fargate_cpu" {
  alarm_name          = "cev-fargate-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "Fargate task CPU above 85% — scanner may be stuck"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = var.ecs_cluster_name
  }
}

resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "cev-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Messages in DLQ — scan jobs are failing after all retries"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = var.dlq_name
  }
}

resource "aws_s3_bucket" "trail_bucket" {
  bucket        = "cev-cloudtrail-logs-${var.account_id}"
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "trail_block" {
  bucket                  = aws_s3_bucket.trail_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "trail_policy" {
  bucket = aws_s3_bucket.trail_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.trail_bucket.arn}/AWSLogs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.trail_bucket.arn
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = "cev-cloudtrail"
  s3_bucket_name                = aws_s3_bucket.trail_bucket.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true

event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = [aws_s3_bucket_policy.trail_policy]

  tags = { Name = "cev-cloudtrail" }
}