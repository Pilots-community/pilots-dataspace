################################################################################
# Database Password Secret
################################################################################

resource "aws_secretsmanager_secret" "db_password" {
  name        = "pilots-connector-db-password-${var.environment}"
  description = "Database password for the pilots-connector RDS instance"
  recovery_window_in_days = 0 # For development, allow immediate deletion

  tags = {
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password

  lifecycle {
    ignore_changes = [secret_string]
  }
}

################################################################################
# RDS Credentials Secret (Structured)
################################################################################

resource "aws_secretsmanager_secret" "rds_credentials" {
  name        = "pilots-connector-rds-credentials-${var.environment}"
  description = "Full RDS credentials for the pilots-connector"
  recovery_window_in_days = 0

  tags = {
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id     = aws_secretsmanager_secret.rds_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = split(":", aws_db_instance.postgres.endpoint)[0]
    port     = 5432
    dbname   = aws_db_instance.postgres.db_name
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
