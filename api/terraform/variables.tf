# api/terraform/variables.tf
# All hardcoded defaults removed — values come from GitHub Secrets
# written into terraform.tfvars by the workflow at deploy time.

variable "aws_region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "account_id" {
  description = "AWS account ID"
}

variable "vpc_id" {
  description = "VPC ID from Ishit's infra"
}

variable "private_subnet_a" {
  description = "Private subnet A ID"
}

variable "private_subnet_b" {
  description = "Private subnet B ID"
}

variable "public_subnet" {
  description = "Public subnet ID"
}

variable "lambda_role_arn" {
  description = "LabRole ARN for Lambda execution"
}

variable "sqs_queue_url" {
  description = "SQS queue URL for job messages"
}

variable "sqs_queue_arn" {
  description = "SQS queue ARN"
}

variable "state_machine_arn" {
  description = "Step Functions state machine ARN"
}

variable "db_password" {
  description = "RDS master password — injected from GitHub Secret, never hardcoded"
  sensitive   = true
}
