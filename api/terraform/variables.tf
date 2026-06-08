variable "aws_region" {
  default = "us-east-1"
}

variable "account_id" {
  default = "469174453369"
}

variable "vpc_id" {
  default = "vpc-038f92f05c8d008ab"
}

variable "private_subnet_a" {
  default = "subnet-0f1d47085356b041a"
}

variable "private_subnet_b" {
  default = "subnet-062fd831d2a0152d0"
}

variable "public_subnet" {
  default = "subnet-0fa918aad9de85318"
}

variable "lambda_sg" {
  default = "sg-07a0ba91c2ffc462f"
}

variable "rds_sg" {
  default = "sg-0291afa76465a499b"
}

variable "lambda_role_arn" {
  default = "arn:aws:iam::126573932591:role/LabRole"
}

variable "sqs_queue_url" {
  default = "https://sqs.us-east-1.amazonaws.com/126573932591/cev-scan-queue"
}

variable "sqs_queue_arn" {
  default = "arn:aws:sqs:us-east-1:126573932591:cev-scan-queue"
}

variable "state_machine_arn" {
  default = "arn:aws:states:us-east-1:126573932591:stateMachine:cev-scan-orchestrator"
}
