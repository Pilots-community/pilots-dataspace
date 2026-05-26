resource "random_password" "db" {
  length  = 32
  special = false
}

# Plain string secret consumed directly by ECS `secrets` (becomes
# $DB_PASSWORD env var in the container).
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.name_prefix}-db-password"
  description             = "RDS master password for ${var.name_prefix}."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}

# JSON blob for tooling that wants username/host/port together (psql wrappers,
# Bruno collections, etc.). Not consumed by EDC services directly.
resource "aws_secretsmanager_secret" "rds_credentials" {
  name                    = "${var.name_prefix}-rds-credentials"
  description             = "Structured RDS credentials for tooling."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id
  secret_string = jsonencode({
    username = var.username
    password = random_password.db.result
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    dbname   = var.initial_db_name
  })
}
