output "address" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "username" {
  value = var.username
}

output "initial_db_name" {
  value = var.initial_db_name
}

output "db_password_secret_arn" {
  value = aws_secretsmanager_secret.db_password.arn
}

output "rds_credentials_secret_arn" {
  value = aws_secretsmanager_secret.rds_credentials.arn
}
