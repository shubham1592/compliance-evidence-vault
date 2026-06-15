# api/terraform/outputs.tf
# References locals from rds.tf and lambda.tf so outputs work
# whether resources were just created or already existed

output "rds_endpoint" {
  value = local.rds_address
}

output "rds_arn" {
  value = can(data.aws_db_instance.existing.db_instance_arn) ? (
    data.aws_db_instance.existing.db_instance_arn
  ) : aws_db_instance.cev_postgres[0].arn
}

output "rds_sg_id" {
  value = local.rds_sg_id
}

output "s3_bucket_name" {
  value = aws_s3_bucket.cev_reports.bucket
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.cev_reports.arn
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
