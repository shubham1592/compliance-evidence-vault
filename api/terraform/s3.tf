# api/terraform/s3.tf
# No data source lookup — S3 bucket is tracked by Terraform state via S3 backend.
# force_destroy = true means re-runs won't fail if bucket already has objects.

variable "s3_bucket_name" {
  description = "S3 bucket name for scan reports and uploads"
}

resource "aws_s3_bucket" "cev_reports" {
  bucket        = var.s3_bucket_name
  force_destroy = true

  tags = {
    Name    = "cev-reports"
    Project = "compliance-evidence-vault"
  }

  lifecycle {
    # Prevents errors if bucket already exists in state from a previous run
    ignore_changes = [bucket]
  }
}

resource "aws_s3_bucket_public_access_block" "cev_reports" {
  bucket = aws_s3_bucket.cev_reports.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Simple locals — no conditional needed
locals {
  s3_bucket_id  = aws_s3_bucket.cev_reports.bucket
  s3_bucket_arn = aws_s3_bucket.cev_reports.arn
}

resource "aws_s3_bucket_cors_configuration" "reports" {
  bucket = aws_s3_bucket.cev_reports.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}
