resource "aws_ecs_task_definition" "db_seeder" {
  family                   = "pilots-db-seeder-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "db-seeder"
      image     = "postgres:16-alpine"
      essential = true
      environment = [
        { name = "PGHOST", value = split(":", aws_db_instance.postgres.endpoint)[0] },
        { name = "PGUSER", value = var.db_username },
        { name = "PGDATABASE", value = "controlplane" },
        { name = "INIT_SQL", value = file("${path.module}/../../config/docker/postgres-connector-init.sql") }
      ]
      secrets = [
        {
          name      = "PGPASSWORD"
          valueFrom = aws_secretsmanager_secret.db_password.arn
        }
      ]
      command = [
        "sh",
        "-c",
        "echo \"$INIT_SQL\" > /tmp/init.sql && psql -f /tmp/init.sql && echo 'Database seeding completed successfully!'"
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "db-seeder"
        }
      }
    }
  ])
}

output "db_seeder_command" {
  value = <<EOF
aws ecs run-task \
  --cluster ${aws_ecs_cluster.pilots.name} \
  --task-definition ${aws_ecs_task_definition.db_seeder.family} \
  --launch-type FARGATE \
  --network-configuration 'awsvpcConfiguration={subnets=[${join(",", data.aws_subnets.default.ids)}],securityGroups=[${aws_security_group.ecs_tasks_sg.id}],assignPublicIp=ENABLED}' \
  --region ${var.region}
EOF
}
