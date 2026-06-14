output "queue_arn" {
  value = aws_sqs_queue.scan_queue.arn
}

output "queue_url" {
  value = aws_sqs_queue.scan_queue.id
}

output "queue_name" {
  value = aws_sqs_queue.scan_queue.name
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}

output "dlq_name" {
  value = aws_sqs_queue.dlq.name
}