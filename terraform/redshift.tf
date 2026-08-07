resource "aws_redshift_subnet_group" "olive_redshift_subnet_group" {
  name       = "olive-redshift-subnet-group"
  subnet_ids = aws_subnet.olive_private_subnet[*].id
  tags       = { Name = "olive-redshift-subnet-group" }
}

resource "aws_redshift_cluster" "olive_redshift_cluster" {
  cluster_identifier = "olive-redshift-cluster"
  database_name      = "olive_analytics"
  master_username    = var.db_username
  master_password    = random_password.olive_db_password.result

  node_type       = var.redshift_node_type
  cluster_type    = "single-node"
  encrypted       = true
  kms_key_id      = aws_kms_key.olive_kms_key.arn

  cluster_subnet_group_name = aws_redshift_subnet_group.olive_redshift_subnet_group.name
  vpc_security_group_ids    = [aws_security_group.olive_redshift_sg.id]

  skip_final_snapshot = true # set to false and add a snapshot identifier for production

  tags = { Name = "olive-redshift-cluster" }
}
