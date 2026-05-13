resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/pilots-${var.environment}"
  retention_in_days = 30
}

resource "aws_ecs_cluster" "pilots" {
  name = "pilots-connector-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_service_discovery_private_dns_namespace" "pilots" {
  name = "pilots.internal"
  vpc  = data.aws_vpc.default.id
}

resource "aws_service_discovery_service" "services" {
  for_each = local.services
  name     = each.key

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.pilots.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_task_definition" "services" {
  for_each = local.services

  family                   = "pilots-${each.key}-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    merge(
      {
        name      = each.key
        image     = each.value.image
        essential = true
        portMappings = [
          for port in each.value.container_ports : {
            containerPort = port
            protocol      = "tcp"
          }
        ]
        environment = each.value.environment
        secrets = contains(["identityhub", "controlplane", "dataplane"], each.key) ? [
          {
            name      = "DB_PASSWORD"
            valueFrom = aws_secretsmanager_secret.db_password.arn
          }
        ] : []
        mountPoints = each.value.mount_points
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = aws_cloudwatch_log_group.ecs.name
            awslogs-region        = var.region
            awslogs-stream-prefix = each.key
          }
        }
      },
      each.value.command == null ? {} : { command = each.value.command },
      (contains(local.ghcr_images, each.key) && var.ghcr_credentials_secret_arn != "") ? {
        repositoryCredentials = {
          credentialsParameter = var.ghcr_credentials_secret_arn
        }
      } : {}
    )
  ])
}

resource "aws_ecs_service" "services" {
  for_each = local.services

  name            = "pilots-${each.key}-${var.environment}"
  cluster         = aws_ecs_cluster.pilots.id
  task_definition = aws_ecs_task_definition.services[each.key].arn
  desired_count   = local.service_desired_counts[each.key]
  launch_type     = "FARGATE"

  force_new_deployment = true

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_tasks_sg.id]
    assign_public_ip = true
  }

  dynamic "load_balancer" {
    for_each = lookup(local.service_load_balancers, each.key, [])
    content {
      target_group_arn = aws_lb_target_group.services[load_balancer.value.route].arn
      container_name   = each.key
      container_port   = load_balancer.value.port
    }
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services[each.key].arn
  }
}
