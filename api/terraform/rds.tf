# Create a security group for RDS in your VPC
resource "aws_security_group" "rds_sg" {
  name        = "cev-rds-sg"
  description = "Allow PostgreSQL access from Lambda"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16"]
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

# Subnet group for RDS
resource "aws_db_subnet_group" "cev" {
  name       = "cev-rds-subnet-group"
  subnet_ids = [var.private_subnet_a, var.private_subnet_b]

  tags = {
    Name    = "cev-rds-subnet-group"
    Project = "compliance-evidence-vault"
  }
}

resource "aws_db_instance" "cev_postgres" {
  identifier        = "cev-postgres"
  engine            = "postgres"
  engine_version    = "16.8"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = "compliancevault"
  username = "cevadmin"
  password = "CEVpassword123!"

  db_subnet_group_name   = aws_db_subnet_group.cev.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  publicly_accessible = false
  skip_final_snapshot = true

  tags = {
    Name    = "cev-postgres"
    Project = "compliance-evidence-vault"
  }
}