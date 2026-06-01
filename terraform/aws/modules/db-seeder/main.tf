locals {
  # Idempotent: only CREATE if the database doesn't already exist. Safe to re-run.
  seed_script = join(" && ", concat(
    [
      "echo 'Connecting to $PGHOST as $PGUSER'",
    ],
    [
      for db in var.databases_to_create :
      "psql -h $PGHOST -U $PGUSER -d postgres -tAc \"SELECT 1 FROM pg_database WHERE datname='${db}'\" | grep -q 1 || psql -h $PGHOST -U $PGUSER -d postgres -c 'CREATE DATABASE ${db}'"
    ],
    [
      "echo 'Database seeding completed successfully!'",
    ],
  ))
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name_prefix}-db-seeder"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([{
    name      = "db-seeder"
    image     = "postgres:16-alpine"
    essential = true
    environment = [
      { name = "PGHOST", value = var.rds_host },
      { name = "PGPORT", value = tostring(var.rds_port) },
      { name = "PGUSER", value = var.db_username },
    ]
    secrets = [
      { name = "PGPASSWORD", valueFrom = var.db_password_secret_arn },
    ]
    command = ["sh", "-c", local.seed_script]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = var.log_group_name
        awslogs-region        = var.region
        awslogs-stream-prefix = "db-seeder"
      }
    }
  }])
}
