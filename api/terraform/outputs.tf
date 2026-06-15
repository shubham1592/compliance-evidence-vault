# api/terraform/outputs.tf
# All references go through locals defined in rds.tf and s3.tf
# Never reference count-based resources directly

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
