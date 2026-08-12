# ---------------------------------------------------------------------------
# AWS DMS - migrates data from olive-legacy-db-instance (see legacy-db.tf)
# into olive-db-instance. When the current legacy source database is
# decommissioned after cutover, point aws_dms_endpoint.olive_dms_source at
# whichever system replaces it and re-run AWS SCT against its schema first.
# ---------------------------------------------------------------------------

# DMS requires an IAM role with this EXACT name ("dms-vpc-role") to manage
# ENIs for replication instances deployed into a VPC. This is a fixed
# requirement from the DMS service itself - it cannot use the olive- prefix.
resource "aws_iam_role" "dms_vpc_role" {
  name = "dms-vpc-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "dms.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dms_vpc_role_policy" {
  role       = aws_iam_role.dms_vpc_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

# DMS also requires an IAM role with this EXACT name ("dms-cloudwatch-logs-role")
# before it will write task logs to CloudWatch - same fixed-name requirement
# as dms-vpc-role above.
resource "aws_iam_role" "dms_cloudwatch_logs_role" {
  name = "dms-cloudwatch-logs-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "dms.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dms_cloudwatch_logs_role_policy" {
  role       = aws_iam_role.dms_cloudwatch_logs_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
}

resource "aws_dms_replication_subnet_group" "olive_dms_subnet_group" {
  replication_subnet_group_id          = "olive-dms-subnet-group"
  replication_subnet_group_description = "Subnet group for olive-dms-instance"
  subnet_ids                           = aws_subnet.olive_private_subnet[*].id

  # Must exist and be attached before DMS will accept a subnet group
  depends_on = [aws_iam_role_policy_attachment.dms_vpc_role_policy]
}

resource "aws_security_group" "olive_dms_sg" {
  name        = "olive-dms-sg"
  description = "Allow DMS replication instance to reach source and target DBs"
  vpc_id      = aws_vpc.olive_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "olive-dms-sg" }
}

resource "aws_dms_replication_instance" "olive_dms_instance" {
  replication_instance_id     = "olive-dms-instance"
  replication_instance_class  = "dms.t3.medium"
  allocated_storage           = 50
  vpc_security_group_ids      = [aws_security_group.olive_dms_sg.id]
  replication_subnet_group_id = aws_dms_replication_subnet_group.olive_dms_subnet_group.id
  publicly_accessible         = false
  tags = { Name = "olive-dms-instance" }
}

resource "aws_dms_endpoint" "olive_dms_source" {
  endpoint_id   = "olive-dms-source"
  endpoint_type = "source"
  engine_name   = "sqlserver"
  server_name   = aws_db_instance.olive_legacy_db_instance.address
  port          = 1433
  username      = var.db_username
  password      = random_password.olive_db_password.result
  database_name = "olive_legacy"
}

resource "aws_dms_endpoint" "olive_dms_target" {
  endpoint_id   = "olive-dms-target"
  endpoint_type = "target"
  engine_name   = "sqlserver"
  server_name   = aws_db_instance.olive_db_instance.address
  port          = 1433
  username      = var.db_username
  password      = random_password.olive_db_password.result
  database_name = "olive"
}

resource "aws_dms_replication_task" "olive_dms_task" {
  replication_task_id      = "olive-dms-task"
  migration_type           = "full-load"
  replication_instance_arn = aws_dms_replication_instance.olive_dms_instance.replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.olive_dms_source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.olive_dms_target.endpoint_arn

  table_mappings = jsonencode({
    rules = [{
      "rule-type" = "selection"
      "rule-id"   = "1"
      "rule-name" = "1"
      "object-locator" = { "schema-name" = "dbo", "table-name" = "Customers" }
      "rule-action" = "include"
    }]
  })
}
