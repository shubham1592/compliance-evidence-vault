variable "sqs_queue_name" {
  description = "Name of the main SQS scan queue"
  type        = string
}

variable "dlq_name" {
  description = "Name of the dead letter queue"
  type        = string
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "orchestrator_lambda_name" {
  description = "Name of the orchestrator Lambda function"
  type        = string
}

variable "reports_bucket_arn" {
  description = "ARN of the S3 reports bucket"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}