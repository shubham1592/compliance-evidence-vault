variable "aws_region" {
  default = "us-east-1"
}

variable "rds_arn" {
  description = "Filled in after Shubham creates RDS"
  type        = string
  default     = ""
}

variable "s3_bucket_arn" {
  description = "Filled in after Shubham creates S3"
  type        = string
  default     = ""
}

variable "state_machine_arn" {
  description = "Filled in after you deploy Step Functions"
  type        = string
  default     = ""
}

variable "failure_handler_lambda_arn" {
  description = "Filled in after Shubham deploys the status-updater Lambda"
  type        = string
  default     = ""
}

variable "ecs_cluster_name" {
  description = "Filled in after Ankita creates the ECS cluster"
  type        = string
  default     = "cev-cluster"
}

variable "orchestrator_lambda_name" {
  description = "Your orchestrator Lambda function name"
  type        = string
  default     = "cev-orchestrator"
}

variable "account_id" {
  description = "Your AWS account ID"
  type        = string
}

variable "alert_email" {
  description = "Email for CloudWatch alarm notifications"
  type        = string
  default     = "arhatia.i@northeastern.edu"
}