terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source     = "./modules/vpc"
  aws_region = var.aws_region
  vpc_cidr   = "10.0.0.0/16"
}

module "sqs" {
  source          = "./modules/sqs"
  lambda_role_arn = module.iam.lambda_role_arn
}

module "iam" {
  source                     = "./modules/iam"
  sqs_queue_arn              = module.sqs.queue_arn
  rds_arn                    = var.rds_arn
  s3_bucket_arn              = var.s3_bucket_arn
  state_machine_arn          = var.state_machine_arn
  failure_handler_lambda_arn = var.failure_handler_lambda_arn
}

module "monitoring" {
  source                   = "./modules/monitoring"
  sqs_queue_name           = module.sqs.queue_name
  dlq_name                 = module.sqs.dlq_name
  ecs_cluster_name         = var.ecs_cluster_name
  orchestrator_lambda_name = var.orchestrator_lambda_name
  reports_bucket_arn       = var.s3_bucket_arn
  account_id               = var.account_id
  alert_email              = var.alert_email
  aws_region               = var.aws_region
}