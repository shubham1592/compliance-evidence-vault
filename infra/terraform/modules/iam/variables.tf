variable "sqs_queue_arn" {
  description = "ARN of the SQS scan queue"
  type        = string
}

variable "rds_arn" {
  description = "ARN of the RDS instance"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the reports S3 bucket"
  type        = string
}

variable "state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  type        = string
}

variable "failure_handler_lambda_arn" {
  description = "ARN of the Lambda that marks jobs FAILED"
  type        = string
}