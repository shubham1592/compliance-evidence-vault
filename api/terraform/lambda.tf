# api/terraform/lambda.tf
# No data source lookups — AWS Academy blocks DescribeSecurityGroups
# Uses var.lambda_sg_id passed in from GitHub Secrets

locals {
  lambda_zip = "${path.module}/../lambda/lambda_function.zip"
}

resource "aws_lambda_function" "cev_api" {
  function_name    = "cev-api-handler"
  role             = var.lambda_role_arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.11"
  filename         = local.lambda_zip
  source_code_hash = filebase64sha256(local.lambda_zip)
  timeout          = 30
  memory_size      = 256

  vpc_config {
    subnet_ids         = [var.private_subnet_a, var.private_subnet_b]
    security_group_ids = [var.lambda_sg_id]
  }

  environment {
    variables = {
      DB_HOST     = local.rds_address
      DB_NAME     = "compliancevault"
      DB_USER     = "cevadmin"
      DB_PASSWORD = var.db_password
      S3_BUCKET   = local.s3_bucket_id
      SQS_URL     = var.sqs_queue_url
    }
  }

  tags = {
    Name    = "cev-api-handler"
    Project = "compliance-evidence-vault"
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

resource "aws_lambda_function" "cev_status_updater" {
  function_name    = "cev-status-updater"
  role             = var.lambda_role_arn
  handler          = "status_updater.lambda_handler"
  runtime          = "python3.11"
  filename         = local.lambda_zip
  source_code_hash = filebase64sha256(local.lambda_zip)
  timeout          = 30
  memory_size      = 128

  vpc_config {
    subnet_ids         = [var.private_subnet_a, var.private_subnet_b]
    security_group_ids = [var.lambda_sg_id]
  }

  environment {
    variables = {
      DB_HOST     = local.rds_address
      DB_NAME     = "compliancevault"
      DB_USER     = "cevadmin"
      DB_PASSWORD = var.db_password
    }
  }

  tags = {
    Name    = "cev-status-updater"
    Project = "compliance-evidence-vault"
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}
