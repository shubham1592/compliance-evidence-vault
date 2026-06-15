# api/terraform/lambda.tf
# DB_PASSWORD now reads from var.db_password (GitHub Secret via tfvars)
# instead of being hardcoded as "CEVpassword123!"

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
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      DB_HOST     = aws_db_instance.cev_postgres.address
      DB_NAME     = "compliancevault"
      DB_USER     = "cevadmin"
      DB_PASSWORD = var.db_password
      S3_BUCKET   = aws_s3_bucket.cev_reports.bucket
      SQS_URL     = var.sqs_queue_url
    }
  }

  tags = {
    Name    = "cev-api-handler"
    Project = "compliance-evidence-vault"
  }
}

resource "aws_security_group" "lambda_sg" {
  name        = "cev-lambda-sg"
  description = "Allow Lambda to reach RDS and AWS services"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "cev-lambda-sg"
    Project = "compliance-evidence-vault"
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
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      DB_HOST     = aws_db_instance.cev_postgres.address
      DB_NAME     = "compliancevault"
      DB_USER     = "cevadmin"
      DB_PASSWORD = var.db_password
    }
  }

  tags = {
    Name    = "cev-status-updater"
    Project = "compliance-evidence-vault"
  }
}
