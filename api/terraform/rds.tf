# api/terraform/rds.tf
#
# RDS and subnet group are created normally without data source lookups.
# The "already exists" errors are solved by the S3 Terraform backend keeping
# state — Terraform knows these resources exist and won't try to recreate them.
#
# Security group still uses a data source because SGs can exist from
# previous partial runs that left no state entry.

# ── RDS security group ────────────────────────────────────────────────────

data "aws_security_groups" "existing_rds_sg" {
  filter {
    name   = "group-name"
    values = ["cev-rds-sg"]
  }
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

resource "aws_security_group" "rds_sg" {
  count       = length(data.aws_security_groups.existing_rds_sg.ids) == 0 ? 1 : 0
  name        = "cev-rds-sg"
  description = "Allow PostgreSQL from Lambda and Fargate"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "Lambda and Fargate to RDS (private VPC range)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "cev-rds-sg"
    Project = "compliance-evidence-vault"
  }
}

locals {
  rds_sg_id = length(data.aws_security_groups.existing_rds_sg.ids) > 0 ? (
    data.aws_security_groups.existing_rds_sg.ids[0]
  ) : aws_security_group.rds_sg[0].id
}

# ── RDS subnet group ──────────────────────────────────────────────────────
# No data source — tracked by Terraform state via S3 backend.
# lifecycle.ignore_changes prevents drift errors on re-runs.

resource "aws_db_subnet_group" "cev" {
  name       = "cev-rds-subnet-group"
  subnet_ids = [var.private_subnet_a, var.private_subnet_b]

  tags = {
    Name    = "cev-rds-subnet-group"
    Project = "compliance-evidence-vault"
  }

  lifecycle {
    ignore_changes = [name, subnet_ids]
  }
}

# ── RDS instance ──────────────────────────────────────────────────────────
# No data source — tracked by Terraform state via S3 backend.

resource "aws_db_instance" "cev_postgres" {
  identifier        = "cev-postgres"
  engine            = "postgres"
  engine_version    = "16.14"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = "compliancevault"
  username = "cevadmin"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.cev.name
  vpc_security_group_ids = [local.rds_sg_id]

  publicly_accessible = false
  skip_final_snapshot = true

  lifecycle {
    # Prevents Terraform from destroying and recreating RDS if
    # password or minor config drifts between runs
    ignore_changes = [password, engine_version]
  }

  tags = {
    Name    = "cev-postgres"
    Project = "compliance-evidence-vault"
  }
}

# Simple local — no conditional needed since resource is always managed
locals {
  rds_address = aws_db_instance.cev_postgres.address
}
