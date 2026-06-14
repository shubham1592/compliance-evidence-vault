output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "trail_bucket_name" {
  value = aws_s3_bucket.trail_bucket.id
}