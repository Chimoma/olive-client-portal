resource "aws_db_subnet_group" "olive_db_subnet_group" {
  name       = "olive-db-subnet-group"
  subnet_ids = aws_subnet.olive_private_subnet[*].id
  tags       = { Name = "olive-db-subnet-group" }
}

resource "aws_db_instance" "olive_db_instance" {
  identifier     = "olive-db-instance"
  engine         = "sqlserver-se"
  engine_version = "15.00.4335.1.v1"
  instance_class = var.db_instance_class

  allocated_storage = 100
  storage_type       = "gp3"
  storage_encrypted  = true
  kms_key_id         = aws_kms_key.olive_kms_key.arn

  username = var.db_username
  password = random_password.olive_db_password.result

  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.olive_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.olive_rds_sg.id]

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:30-mon:05:30"

  deletion_protection      = true
  skip_final_snapshot      = false
  final_snapshot_identifier = "olive-db-final-snapshot"

  enabled_cloudwatch_logs_exports = ["error"]

  # SQL Server Multi-AZ provisioning routinely takes 60-90 minutes -
  # the default 40 minute timeout is too short for this engine/config.
  timeouts {
    create = "120m"
    update = "120m"
    delete = "60m"
  }

  tags = { Name = "olive-db-instance" }
}
