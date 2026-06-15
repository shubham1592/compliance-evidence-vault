# compute/terraform/main.tf
# account_id removed from hardcoded local — reads from var.account_id

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

variable "aws_region"                 { default = "us-east-1" }
variable "project"                    { default = "compliance-vault" }
variable "account_id"                 { description = "AWS account ID" }
variable "vpc_id"                     { description = "VPC ID" }
variable "private_subnet_ids"         { type = list(string) }
variable "rds_security_group_id"      { description = "RDS security group ID" }
variable "fargate_security_group_id"  { description = "Fargate security group ID" }
variable "report_bucket_name"         { description = "S3 bucket for reports" }
variable "db_host"                    { description = "RDS endpoint" }
variable "db_name"                    { default = "compliancevault" }
variable "db_user"                    { default = "cevadmin" }
variable "ecr_image_tag"              { default = "latest" }

locals {
  prefix   = "${var.project}-compute"
  lab_role = "arn:aws:iam::${var.account_id}:role/LabRole"
}

# ---------------------------------------------------------------------------
# ECR
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "sast" {
  name                 = "${local.prefix}-sast-scanner"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
  tags = { Component = "ankita-compute", Owner = "ankita" }
}

resource "aws_ecr_repository" "pentest" {
  name                 = "${local.prefix}-pentest-scanner"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
  tags = { Component = "ankita-compute", Owner = "ankita" }
}

resource "aws_ecr_lifecycle_policy" "sast" {
  repository = aws_ecr_repository.sast.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "pentest" {
  repository = aws_ecr_repository.pentest.name
  policy     = aws_ecr_lifecycle_policy.sast.policy
}

# ---------------------------------------------------------------------------
# CloudWatch log groups
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "sast" {
  name              = "/ecs/${local.prefix}/sast-scanner"
  retention_in_days = 30
  tags              = { Component = "ankita-compute" }
}

resource "aws_cloudwatch_log_group" "pentest" {
  name              = "/ecs/${local.prefix}/pentest-scanner"
  retention_in_days = 30
  tags              = { Component = "ankita-compute" }
}

# ---------------------------------------------------------------------------
# ECS cluster
# ---------------------------------------------------------------------------

resource "aws_ecs_cluster" "scanners" {
  name = "${local.prefix}-cluster"
  setting { name = "containerInsights", value = "enabled" }
  tags = { Component = "ankita-compute", Owner = "ankita" }
}

resource "aws_ecs_cluster_capacity_providers" "scanners" {
  cluster_name       = aws_ecs_cluster.scanners.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# ---------------------------------------------------------------------------
# ECS task definitions
# DB_PASSWORD, JOB_ID, S3_KEY/TARGET_URL injected at runtime by Step Functions
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "sast" {
  family                   = "${local.prefix}-sast"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = local.lab_role
  task_role_arn            = local.lab_role

  container_definitions = jsonencode([{
    name      = "sast-scanner"
    image     = "${aws_ecr_repository.sast.repository_url}:${var.ecr_image_tag}"
    essential = true
    environment = [
      { name = "REPORT_BUCKET", value = var.report_bucket_name },
      { name = "DB_HOST",       value = var.db_host },
      { name = "DB_NAME",       value = var.db_name },
      { name = "DB_USER",       value = var.db_user },
      { name = "DB_SSLMODE",    value = "require" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.sast.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = { Component = "ankita-compute", Owner = "ankita" }
}

resource "aws_ecs_task_definition" "pentest" {
  family                   = "${local.prefix}-pentest"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = local.lab_role
  task_role_arn            = local.lab_role

  container_definitions = jsonencode([{
    name      = "pentest-scanner"
    image     = "${aws_ecr_repository.pentest.repository_url}:${var.ecr_image_tag}"
    essential = true
    environment = [
      { name = "REPORT_BUCKET", value = var.report_bucket_name },
      { name = "DB_HOST",       value = var.db_host },
      { name = "DB_NAME",       value = var.db_name },
      { name = "DB_USER",       value = var.db_user },
      { name = "DB_SSLMODE",    value = "require" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.pentest.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = { Component = "ankita-compute", Owner = "ankita" }
}

# ---------------------------------------------------------------------------
# S3 bucket + lifecycle
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "reports" {
  bucket        = var.report_bucket_name
  force_destroy = true
  tags          = { Component = "ankita-compute", Owner = "ankita" }
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket                  = aws_s3_bucket.reports.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket     = aws_s3_bucket.reports.id
  depends_on = [aws_s3_bucket.reports]

  rule {
    id     = "reports-archive"
    status = "Enabled"
    filter { prefix = "reports/" }
    transition  { days = 90,   storage_class = "GLACIER" }
    expiration  { days = 2555 }
  }

  rule {
    id     = "uploads-cleanup"
    status = "Enabled"
    filter { prefix = "uploads/" }
    expiration { days = 7 }
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "sast_task_definition_arn"    { value = aws_ecs_task_definition.sast.arn }
output "pentest_task_definition_arn" { value = aws_ecs_task_definition.pentest.arn }
output "ecs_cluster_arn"             { value = aws_ecs_cluster.scanners.arn }
output "sast_ecr_url"                { value = aws_ecr_repository.sast.repository_url }
output "pentest_ecr_url"             { value = aws_ecr_repository.pentest.repository_url }
output "report_bucket_name"          { value = aws_s3_bucket.reports.bucket }
output "sast_log_group"              { value = aws_cloudwatch_log_group.sast.name }
output "pentest_log_group"           { value = aws_cloudwatch_log_group.pentest.name }
