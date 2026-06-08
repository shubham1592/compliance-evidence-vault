output "rds_endpoint" {
  value = aws_db_instance.cev_postgres.endpoint
}

output "rds_arn" {
  value = aws_db_instance.cev_postgres.arn
}

output "s3_bucket_name" {
  value = aws_s3_bucket.cev_reports.bucket
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.cev_reports.arn
}

output "rds_sg_id" {
  value = aws_security_group.rds_sg.id
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