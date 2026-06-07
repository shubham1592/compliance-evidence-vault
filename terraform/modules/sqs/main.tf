resource "aws_sqs_queue" "dlq" {
  name                      = "cev-scan-dlq"
  message_retention_seconds = 1209600
  tags = { Name = "cev-scan-dlq" }
}

resource "aws_sqs_queue" "scan_queue" {
  name                       = "cev-scan-queue"
  visibility_timeout_seconds = 900
  message_retention_seconds  = 86400

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = "cev-scan-queue" }
}

resource "aws_sqs_queue_policy" "scan_queue_policy" {
  queue_url = aws_sqs_queue.scan_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = var.lambda_role_arn }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.scan_queue.arn
      },
      {
        Effect    = "Allow"
        Principal = { AWS = var.lambda_role_arn }
        Action    = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource  = aws_sqs_queue.scan_queue.arn
      }
    ]
  })
}