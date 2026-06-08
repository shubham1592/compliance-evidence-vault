# Package the Lambda code into a zip file
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "cev_api" {
  function_name    = "cev-api-handler"
  role             = var.lambda_role_arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
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
      DB_PASSWORD = "CEVpassword123!"
      S3_BUCKET   = aws_s3_bucket.cev_reports.bucket
      SQS_URL     = var.sqs_queue_url
    }
  }

  tags = {
    Name    = "cev-api-handler"
    Project = "compliance-evidence-vault"
  }
}

# Security group for Lambda
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

# Status updater Lambda — called by Ankita's scanners to mark jobs COMPLETED/FAILED
resource "aws_lambda_function" "cev_status_updater" {
  function_name    = "cev-status-updater"
  role             = var.lambda_role_arn
  handler          = "status_updater.lambda_handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
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
      DB_PASSWORD = "CEVpassword123!"
    }
  }

  tags = {
    Name    = "cev-status-updater"
    Project = "compliance-evidence-vault"
  }
}