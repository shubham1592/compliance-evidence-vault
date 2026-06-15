# api/terraform/variables.tf
# All values come from GitHub Secrets via terraform.tfvars written by workflow
# No defaults — forces explicit values for everything

variable "aws_region" {
  default = "us-east-1"
}

variable "account_id" {
  description = "AWS account ID"
}

variable "vpc_id" {
  description = "VPC ID"
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
  description = "LabRole ARN for Lambda"
}

variable "lambda_sg_id" {
  description = "Existing Lambda security group ID — from Phase 1 outputs"
}

variable "rds_sg_id" {
  description = "Existing RDS security group ID — from Phase 1 outputs"
}

variable "sqs_queue_url" {
  description = "SQS queue URL"
}

variable "sqs_queue_arn" {
  description = "SQS queue ARN"
}

variable "state_machine_arn" {
  description = "Step Functions state machine ARN"
}

variable "db_password" {
  description = "RDS master password"
  sensitive   = true
}

variable "s3_bucket_name" {
  description = "S3 bucket name for reports and uploads"
}
