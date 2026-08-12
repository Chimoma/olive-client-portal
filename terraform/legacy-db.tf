# ---------------------------------------------------------------------------
# Legacy source database - the pre-modernization SQL Server instance that
# AWS DMS (dms.tf) migrates data from into olive-db-instance. Once cutover
# is complete and the migration is verified, this instance can be
# decommissioned (see README.md Step 10).
# ---------------------------------------------------------------------------

resource "aws_security_group" "olive_legacy_db_sg" {
  name        = "olive-legacy-db-sg"
  description = "Allow SQL Server traffic from DMS to the legacy source DB"
  vpc_id      = aws_vpc.olive_vpc.id

  ingress {
    description     = "SQL Server from DMS"
    from_port       = 1433
    to_port         = 1433
    protocol        = "tcp"
    security_groups = [aws_security_group.olive_dms_sg.id]
  }

  # Used for the initial data load only - tighten to specific IP ranges
  # (or remove entirely) once the migration is complete.
  ingress {
    description = "SQL Server for initial data load"
    from_port   = 1433
    to_port     = 1433
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "olive-legacy-db-sg" }
}

resource "aws_db_subnet_group" "olive_legacy_db_subnet_group" {
  name = "olive-legacy-db-subnet-group"
  # Public subnets, unlike olive-db-instance's subnet group - this instance
  # needs a real path in from the internet for the one-time data load.
  subnet_ids = aws_subnet.olive_public_subnet[*].id
  tags       = { Name = "olive-legacy-db-subnet-group" }
}

resource "aws_db_instance" "olive_legacy_db_instance" {
  identifier     = "olive-legacy-db-instance"
  engine         = "sqlserver-ex"
  engine_version = "15.00.4335.1.v1"
  instance_class = "db.t3.small"

  allocated_storage = 20
  storage_encrypted = true
  kms_key_id        = aws_kms_key.olive_kms_key.arn

  username = var.db_username
  password = random_password.olive_db_password.result

  publicly_accessible    = true # required for the initial data load; restrict after cutover
  db_subnet_group_name   = aws_db_subnet_group.olive_legacy_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.olive_legacy_db_sg.id]

  multi_az                = false
  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false

  timeouts {
    create = "120m"
    delete = "60m"
  }

  tags = { Name = "olive-legacy-db-instance" }
}

output "olive_legacy_db_endpoint" {
  description = "Endpoint of the legacy source database"
  value       = aws_db_instance.olive_legacy_db_instance.address
}
