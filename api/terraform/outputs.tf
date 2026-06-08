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