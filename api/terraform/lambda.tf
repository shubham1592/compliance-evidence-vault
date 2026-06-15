# api/terraform/lambda.tf

locals {
  lambda_zip = "${path.module}/../lambda/lambda_function.zip"
}

# ── Security group ─────────────────────────────────────────────────────────

data "aws_security_groups" "existing_lambda_sg" {
  filter {
    name   = "group-name"
    values = ["cev-lambda-sg"]
  }
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

resource "aws_security_group" "lambda_sg" {
  count       = length(data.aws_security_groups.existing_lambda_sg.ids) == 0 ? 1 : 0
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

# Always resolves to the SG ID whether we just created it or it already existed
locals {
  lambda_sg_id = length(data.aws_security_groups.existing_lambda_sg.ids) > 0 ? (
    data.aws_security_groups.existing_lambda_sg.ids[0]
  ) : aws_security_group.lambda_sg[0].id
}

# ── Lambda functions ───────────────────────────────────────────────────────
# Use local.rds_address and local.s3_bucket_id from rds.tf and s3.tf
# Never reference aws_db_instance.cev_postgres or aws_s3_bucket.cev_reports
# directly because those have count set

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
    security_group_ids = [local.lambda_sg_id]
  }

  environment {
    variables = {
      DB_HOST     = local.rds_address      # from rds.tf local
      DB_NAME     = "compliancevault"
      DB_USER     = "cevadmin"
      DB_PASSWORD = var.db_password
      S3_BUCKET   = local.s3_bucket_id     # from s3.tf local
      SQS_URL     = var.sqs_queue_url
    }
  }

  tags = {
    Name    = "cev-api-handler"
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
    security_group_ids = [local.lambda_sg_id]
  }

  environment {
    variables = {
      DB_HOST     = local.rds_address      # from rds.tf local
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
