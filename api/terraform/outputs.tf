# api/terraform/outputs.tf

output "rds_endpoint" {
  value = local.rds_address
}

output "rds_arn" {
  value = aws_db_instance.cev_postgres.arn
}

output "rds_sg_id" {
  value = local.rds_sg_id
}

output "s3_bucket_name" {
  value = local.s3_bucket_id
}

output "s3_bucket_arn" {
  value = local.s3_bucket_arn
}

output "api_gateway_url" {
  value = "${aws_api_gateway_stage.cev.invoke_url}/jobs"
}

output "api_key_id" {
  value = aws_api_gateway_api_key.cev.id
}

output "lambda_arn" {
  value = aws_lambda_function.cev_api.arn
}

output "status_updater_arn" {
  value = aws_lambda_function.cev_status_updater.arn
}
