terraform {
  backend "s3" {
    bucket = "cev-tf-state-126573932591"
    key    = "api/terraform.tfstate"
    region = "us-east-1"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}