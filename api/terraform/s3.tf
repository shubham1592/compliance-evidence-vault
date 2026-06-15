# api/terraform/s3.tf
# Bucket name comes from var.s3_bucket_name — set in tfvars from GitHub Secret
# Uses data source so re-runs don't fail if bucket already exists

variable "s3_bucket_name" {
  description = "S3 bucket name for scan reports and uploads"
}

data "aws_s3_bucket" "existing_reports" {
  bucket = var.s3_bucket_name
}

resource "aws_s3_bucket" "cev_reports" {
  # Only create if bucket doesn't already exist
  count         = can(data.aws_s3_bucket.existing_reports.id) ? 0 : 1
  bucket        = var.s3_bucket_name
  force_destroy = true

  tags = {
    Name    = "cev-reports"
    Project = "compliance-evidence-vault"
  }
}

resource "aws_s3_bucket_public_access_block" "cev_reports" {
  count  = can(data.aws_s3_bucket.existing_reports.id) ? 0 : 1
  bucket = aws_s3_bucket.cev_reports[0].id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Always resolves to the bucket regardless of whether we created it
locals {
  s3_bucket_id  = can(data.aws_s3_bucket.existing_reports.id) ? data.aws_s3_bucket.existing_reports.id : aws_s3_bucket.cev_reports[0].id
  s3_bucket_arn = can(data.aws_s3_bucket.existing_reports.arn) ? data.aws_s3_bucket.existing_reports.arn : aws_s3_bucket.cev_reports[0].arn
}
