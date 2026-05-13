resource "aws_db_instance" "postgres" {
  identifier           = "pilots-connector-${var.environment}"
  allocated_storage    = 20
  storage_type         = "gp3"
  engine               = "postgres"
  engine_version       = "16"
  instance_class       = var.db_instance_class
  db_name              = "controlplane"
  username             = var.db_username
  password             = var.db_password
  parameter_group_name = aws_db_parameter_group.postgres.name
  skip_final_snapshot  = true
  publicly_accessible  = false # Keep it private, ECS tasks are in the same VPC

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.postgres.id

  lifecycle {
    ignore_changes = [password]
  }

  tags = {
    Name        = "pilots-connector-db"
    Environment = var.environment
  }
}

resource "aws_db_parameter_group" "postgres" {
  name   = "pilots-connector-pg16"
  family = "postgres16"

  parameter {
    name  = "log_connections"
    value = "1"
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "pilots-connector-db-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "Pilots DB Subnet Group"
  }
}

resource "null_resource" "db_init_instruction" {
  depends_on = [aws_db_instance.postgres]

  provisioner "local-exec" {
    command = "echo 'RDS Instance Ready. To initialize additional databases, run: PGPASSWORD=${var.db_password} psql -h ${split(":", aws_db_instance.postgres.endpoint)[0]} -U ${var.db_username} -d controlplane -f ../../config/docker/postgres-connector-init.sql'"
  }
}
