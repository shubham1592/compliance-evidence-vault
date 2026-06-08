resource "aws_s3_bucket" "cev_reports" {
  bucket        = "cev-scan-reports-${var.account_id}"
  force_destroy = true

  tags = {
    Name    = "cev-scan-reports"
    Project = "compliance-evidence-vault"
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "cev_reports" {
  bucket = aws_s3_bucket.cev_reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle: move reports to Glacier after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "cev_reports" {
  bucket = aws_s3_bucket.cev_reports.id

  rule {
    id     = "archive-to-glacier"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}