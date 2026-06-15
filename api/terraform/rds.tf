# api/terraform/rds.tf
# Uses data source lookups so re-runs never fail with "already exists"

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

data "aws_db_subnet_group" "existing" {
  name = "cev-rds-subnet-group"
}

resource "aws_db_subnet_group" "cev" {
  # Only create if the data source lookup fails (resource doesn't exist)
  # We handle this with a try() — if data source errors, we create
  count      = can(data.aws_db_subnet_group.existing.id) ? 0 : 1
  name       = "cev-rds-subnet-group"
  subnet_ids = [var.private_subnet_a, var.private_subnet_b]

  tags = {
    Name    = "cev-rds-subnet-group"
    Project = "compliance-evidence-vault"
  }
}

locals {
  db_subnet_group_name = can(data.aws_db_subnet_group.existing.id) ? (
    data.aws_db_subnet_group.existing.name
  ) : aws_db_subnet_group.cev[0].name
}

# ── RDS instance ──────────────────────────────────────────────────────────

data "aws_db_instance" "existing" {
  db_instance_identifier = "cev-postgres"
}

resource "aws_db_instance" "cev_postgres" {
  count             = can(data.aws_db_instance.existing.id) ? 0 : 1
  identifier        = "cev-postgres"
  engine            = "postgres"
  engine_version    = "16.8"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = "compliancevault"
  username = "cevadmin"
  password = var.db_password

  db_subnet_group_name   = local.db_subnet_group_name
  vpc_security_group_ids = [local.rds_sg_id]

  publicly_accessible = false
  skip_final_snapshot = true

  tags = {
    Name    = "cev-postgres"
    Project = "compliance-evidence-vault"
  }
}

# Local that always resolves to the RDS address whether we created it or not
locals {
  rds_address = can(data.aws_db_instance.existing.address) ? (
    data.aws_db_instance.existing.address
  ) : aws_db_instance.cev_postgres[0].address
}
