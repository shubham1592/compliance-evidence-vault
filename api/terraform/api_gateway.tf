resource "aws_api_gateway_rest_api" "cev" {
  name        = "cev-api"
  description = "Compliance Evidence Vault API"

  tags = {
    Project = "compliance-evidence-vault"
  }
}

# API key for auth
resource "aws_api_gateway_api_key" "cev" {
  name    = "cev-api-key"
  enabled = true
}

# Usage plan with throttling
resource "aws_api_gateway_usage_plan" "cev" {
  name = "cev-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.cev.id
    stage  = aws_api_gateway_stage.cev.stage_name
  }

  throttle_settings {
    rate_limit  = 100
    burst_limit = 50
  }
}

resource "aws_api_gateway_usage_plan_key" "cev" {
  key_id        = aws_api_gateway_api_key.cev.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.cev.id
}

# /jobs resource
resource "aws_api_gateway_resource" "jobs" {
  rest_api_id = aws_api_gateway_rest_api.cev.id
  parent_id   = aws_api_gateway_rest_api.cev.root_resource_id
  path_part   = "jobs"
}

# /jobs/{id} resource
resource "aws_api_gateway_resource" "job_id" {
  rest_api_id = aws_api_gateway_rest_api.cev.id
  parent_id   = aws_api_gateway_resource.jobs.id
  path_part   = "{id}"
}

# POST /jobs
resource "aws_api_gateway_method" "post_jobs" {
  rest_api_id      = aws_api_gateway_rest_api.cev.id
  resource_id      = aws_api_gateway_resource.jobs.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "post_jobs" {
  rest_api_id             = aws_api_gateway_rest_api.cev.id
  resource_id             = aws_api_gateway_resource.jobs.id
  http_method             = aws_api_gateway_method.post_jobs.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.cev_api.invoke_arn
}

# GET /jobs
resource "aws_api_gateway_method" "get_jobs" {
  rest_api_id      = aws_api_gateway_rest_api.cev.id
  resource_id      = aws_api_gateway_resource.jobs.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "get_jobs" {
  rest_api_id             = aws_api_gateway_rest_api.cev.id
  resource_id             = aws_api_gateway_resource.jobs.id
  http_method             = aws_api_gateway_method.get_jobs.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.cev_api.invoke_arn
}

# GET /jobs/{id}
resource "aws_api_gateway_method" "get_job_id" {
  rest_api_id      = aws_api_gateway_rest_api.cev.id
  resource_id      = aws_api_gateway_resource.job_id.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "get_job_id" {
  rest_api_id             = aws_api_gateway_rest_api.cev.id
  resource_id             = aws_api_gateway_resource.job_id.id
  http_method             = aws_api_gateway_method.get_job_id.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.cev_api.invoke_arn
}

# Deploy the API
resource "aws_api_gateway_deployment" "cev" {
  rest_api_id = aws_api_gateway_rest_api.cev.id

  depends_on = [
    aws_api_gateway_integration.post_jobs,
    aws_api_gateway_integration.get_jobs,
    aws_api_gateway_integration.get_job_id
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "cev" {
  rest_api_id   = aws_api_gateway_rest_api.cev.id
  deployment_id = aws_api_gateway_deployment.cev.id
  stage_name    = "prod"
}

# Allow API Gateway to invoke the Lambda
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cev_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.cev.execution_arn}/*/*"
}