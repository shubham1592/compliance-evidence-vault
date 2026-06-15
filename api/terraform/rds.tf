# api/terraform/rds.tf
# No data source lookups — AWS Academy blocks DescribeSecurityGroups
# Existing SG IDs passed in as variables from GitHub Secrets

resource "aws_db_subnet_group" "cev" {
  name       = "cev-rds-subnet-group"
  subnet_ids = [var.private_subnet_a, var.private_subnet_b]

  tags = {
    Name    = "cev-rds-subnet-group"
    Project = "compliance-evidence-vault"
  }

  lifecycle {
    ignore_changes  = [name, subnet_ids]
    # If subnet group already exists Terraform will error —
    # run: terraform import aws_db_subnet_group.cev cev-rds-subnet-group
  }
}

resource "aws_db_instance" "cev_postgres" {
  identifier        = "cev-postgres"
  engine            = "postgres"
  engine_version    = "16.3"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = "compliancevault"
  username = "cevadmin"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.cev.name
  vpc_security_group_ids = [var.rds_sg_id]

  publicly_accessible = false
  skip_final_snapshot = true

  lifecycle {
    ignore_changes = [password, engine_version]
  }

  tags = {
    Name    = "cev-postgres"
    Project = "compliance-evidence-vault"
  }
}

locals {
  rds_address = aws_db_instance.cev_postgres.address
}
