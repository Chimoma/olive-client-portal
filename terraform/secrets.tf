# Terraform generates a strong random password at apply time - it is never
# typed by a human and never committed to version control.
resource "random_password" "olive_db_password" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()-_=+"
}

resource "aws_secretsmanager_secret" "olive_db_secret" {
  name                    = "olive-db-secret"
  description             = "Master credentials for olive-db-instance"
  kms_key_id              = aws_kms_key.olive_kms_key.arn
  recovery_window_in_days = 7
  tags = { Name = "olive-db-secret" }
}

resource "aws_secretsmanager_secret_version" "olive_db_secret_version" {
  secret_id = aws_secretsmanager_secret.olive_db_secret.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.olive_db_password.result
    engine   = "sqlserver"
    host     = aws_db_instance.olive_db_instance.address
    port     = 1433
    dbname   = "olive"
  })
}
