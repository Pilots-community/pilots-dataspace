locals {
  port_mappings = [
    for p in var.container_ports : {
      containerPort = p
      protocol      = "tcp"
    }
  ]

  mount_points = [
    for m in var.mounts : {
      sourceVolume  = m.source_volume
      containerPath = m.container_path
      readOnly      = m.read_only
    }
  ]

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = var.name
    }
  }

  repository_credentials = var.ghcr_credentials_secret_arn != "" ? {
    repositoryCredentials = { credentialsParameter = var.ghcr_credentials_secret_arn }
  } : {}

  healthcheck_block = var.healthcheck == null ? {} : {
    healthCheck = {
      command     = var.healthcheck.command
      interval    = var.healthcheck.interval
      timeout     = var.healthcheck.timeout
      retries     = var.healthcheck.retries
      startPeriod = var.healthcheck.start_period
    }
  }

  command_block    = var.command == null ? {} : { command = var.command }
  entrypoint_block = var.entrypoint == null ? {} : { entryPoint = var.entrypoint }

  container_def = merge(
    {
      name             = var.name
      image            = var.image
      essential        = true
      portMappings     = local.port_mappings
      environment      = var.environment
      secrets          = var.secrets
      mountPoints      = local.mount_points
      logConfiguration = local.log_configuration
    },
    local.command_block,
    local.entrypoint_block,
    local.healthcheck_block,
    local.repository_credentials,
  )
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name_prefix}-${var.name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  dynamic "volume" {
    for_each = var.mounts
    content {
      name = volume.value.source_volume

      efs_volume_configuration {
        file_system_id     = volume.value.file_system_id
        transit_encryption = "ENABLED"

        authorization_config {
          access_point_id = volume.value.access_point_id
          iam             = "DISABLED"
        }
      }
    }
  }

  container_definitions = jsonencode([local.container_def])
}
