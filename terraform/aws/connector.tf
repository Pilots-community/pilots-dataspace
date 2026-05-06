locals {
  private_key_pem = trimspace(file("${path.module}/../../config/certs/private-key.pem"))
  public_key_pem  = trimspace(file("${path.module}/../../config/certs/public-key.pem"))
  issuer_did_json = trimspace(file("${path.module}/../../deployment/assets/issuer/did.json"))
  nginx_conf      = trimspace(file("${path.module}/../../deployment/nginx.conf"))

  postgres_init_sql = trimspace(file("${path.module}/../../config/docker/postgres-connector-init.sql"))

  identityhub_config = replace(
    replace(
      replace(
        replace(
          replace(
            file("${path.module}/../../config/docker/identityhub-connector.properties"),
            "edc.hostname=identityhub",
            "edc.hostname=${var.root_domain}"
          ),
          "edc.iam.did.web.use.https=false",
          "edc.iam.did.web.use.https=true"
        ),
        "did:web:identityhub%3A7093",
        "did:web:${var.root_domain}%3A7093"
      ),
      "jdbc:postgresql://postgres:5432/identityhub",
      "jdbc:postgresql://postgres.pilots.internal:5432/identityhub"
    ),
    "http://vault:8200",
    "http://vault.pilots.internal:8200"
  )

  controlplane_config = replace(
    replace(
      replace(
        replace(
          replace(
            replace(
              replace(
                file("${path.module}/../../config/docker/controlplane-connector.properties"),
                "edc.participant.id=did:web:identityhub%3A7093",
                "edc.participant.id=did:web:${var.root_domain}%3A7093"
              ),
              "edc.hostname=controlplane",
              "edc.hostname=${var.root_domain}"
            ),
            "edc.dsp.callback.address=http://controlplane:19194/protocol",
            "edc.dsp.callback.address=https://${var.root_domain}/dsp/protocol"
          ),
          "did:web:identityhub%3A7093",
          "did:web:${var.root_domain}%3A7093"
        ),
        "edc.iam.did.web.use.https=false",
        "edc.iam.did.web.use.https=true"
      ),
      "http://identityhub:7096/api/sts/token",
      "http://identityhub.pilots.internal:7096/api/sts/token"
    ),
    "jdbc:postgresql://postgres:5432/controlplane",
    "jdbc:postgresql://postgres.pilots.internal:5432/controlplane"
  )

  controlplane_config_final = replace(
    local.controlplane_config,
    "http://vault:8200",
    "http://vault.pilots.internal:8200"
  )

  dataplane_config = replace(
    replace(
      replace(
        replace(
          replace(
            replace(
              file("${path.module}/../../config/docker/dataplane-connector.properties"),
              "edc.hostname=dataplane",
              "edc.hostname=${var.root_domain}"
            ),
            "http://controlplane:19192/control/v1/dataplanes",
            "http://controlplane.pilots.internal:19192/control/v1/dataplanes"
          ),
          "edc.transfer.proxy.token.signer.privatekey.path=/app/certs/private-key.pem",
          "edc.transfer.proxy.token.signer.privatekey.path=/tmp/private-key.pem"
        ),
        "edc.transfer.proxy.token.verifier.publickey.path=/app/certs/public-key.pem",
        "edc.transfer.proxy.token.verifier.publickey.path=/tmp/public-key.pem"
      ),
      "edc.dataplane.api.public.baseurl=http://dataplane:38185/public",
      "edc.dataplane.api.public.baseurl=https://${var.root_domain}/data/public"
    ),
    "jdbc:postgresql://postgres:5432/dataplane",
    "jdbc:postgresql://postgres.pilots.internal:5432/dataplane"
  )

  dataplane_config_final = replace(
    local.dataplane_config,
    "http://vault:8200",
    "http://vault.pilots.internal:8200"
  )

  services = {
    postgres = {
      image          = "postgres:16-alpine"
      container_port = 5432
      cpu            = 256
      memory         = 512
      environment = [
        { name = "POSTGRES_USER", value = "edc" },
        { name = "POSTGRES_PASSWORD", value = "edc" },
        { name = "POSTGRES_DB", value = "controlplane" },
        { name = "POSTGRES_INIT_SQL", value = local.postgres_init_sql }
      ]
      command = [
        "sh",
        "-c",
        "printf '%s\n' \"$POSTGRES_INIT_SQL\" > /docker-entrypoint-initdb.d/init.sql && exec docker-entrypoint.sh postgres"
      ]
      mount_points = [
        { sourceVolume = "postgres-data", containerPath = "/var/lib/postgresql/data", readOnly = false }
      ]
    }
    vault = {
      image          = "hashicorp/vault:1.15"
      container_port = 8200
      cpu            = 256
      memory         = 512
      environment    = []
      command        = ["vault", "server", "-dev", "-dev-root-token-id=root-token", "-dev-listen-address=0.0.0.0:8200"]
      mount_points   = []
    }
    did-server = {
      image          = "nginx:alpine"
      container_port = 9876
      cpu            = 256
      memory         = 512
      environment = [
        { name = "NGINX_CONF", value = local.nginx_conf },
        { name = "ISSUER_DID_JSON", value = local.issuer_did_json }
      ]
      command = [
        "sh",
        "-c",
        "mkdir -p /usr/share/nginx/html/.well-known && printf '%s\n' \"$NGINX_CONF\" > /etc/nginx/conf.d/default.conf && printf '%s\n' \"$ISSUER_DID_JSON\" > /usr/share/nginx/html/.well-known/did.json && exec nginx -g 'daemon off;'"
      ]
      mount_points = []
    }
    dashboard = {
      image          = "ghcr.io/pilots-community/pilots-dataspace/dashboard:${var.image_tag}"
      container_port = 80
      cpu            = var.ecs_cpu
      memory         = var.ecs_memory
      environment    = []
      command        = null
      mount_points   = []
    }
    identityhub = {
      image          = "ghcr.io/pilots-community/pilots-dataspace/identityhub:${var.image_tag}"
      container_port = 7091
      cpu            = var.ecs_cpu
      memory         = var.ecs_memory
      environment = [
        { name = "IDENTITYHUB_CONFIG", value = local.identityhub_config }
      ]
      command = [
        "sh",
        "-c",
        "printf '%s\n' \"$IDENTITYHUB_CONFIG\" > /tmp/identityhub-connector.properties && exec java -Djava.security.egd=file:/dev/urandom -Dedc.fs.config=/tmp/identityhub-connector.properties -jar identityhub.jar"
      ]
      mount_points = []
    }
    controlplane = {
      image          = "ghcr.io/pilots-community/pilots-dataspace/controlplane:${var.image_tag}"
      container_port = 19194
      cpu            = var.ecs_cpu
      memory         = var.ecs_memory
      environment = [
        { name = "CONTROLPLANE_CONFIG", value = local.controlplane_config_final }
      ]
      command = [
        "sh",
        "-c",
        "unset WEB_HTTP_PORT WEB_HTTP_PATH && printf '%s\n' \"$CONTROLPLANE_CONFIG\" > /tmp/controlplane-connector.properties && exec java -Djava.security.egd=file:/dev/urandom -Dedc.fs.config=/tmp/controlplane-connector.properties -jar edc-controlplane.jar"
      ]
      mount_points = []
    }
    dataplane = {
      image          = "ghcr.io/pilots-community/pilots-dataspace/dataplane:${var.image_tag}"
      container_port = 38185
      cpu            = var.ecs_cpu
      memory         = var.ecs_memory
      environment = [
        { name = "DATAPLANE_CONFIG", value = local.dataplane_config_final },
        { name = "PRIVATE_KEY_PEM", value = local.private_key_pem },
        { name = "PUBLIC_KEY_PEM", value = local.public_key_pem }
      ]
      command = [
        "sh",
        "-c",
        "unset WEB_HTTP_PORT WEB_HTTP_PATH && printf '%s\n' \"$DATAPLANE_CONFIG\" > /tmp/dataplane-connector.properties && printf '%s\n' \"$PRIVATE_KEY_PEM\" > /tmp/private-key.pem && printf '%s\n' \"$PUBLIC_KEY_PEM\" > /tmp/public-key.pem && exec java -Djava.security.egd=file:/dev/urandom -Dedc.fs.config=/tmp/dataplane-connector.properties -jar edc-dataplane.jar"
      ]
      mount_points = []
    }
  }

  service_load_balancers = {
    dashboard = [{ route = "dashboard", port = 80 }]
    identityhub = [
      { route = "credentials", port = 7091 },
      { route = "did-api", port = 7093 }
    ]
    controlplane = [{ route = "dsp", port = 19194 }]
    dataplane    = [{ route = "data", port = 38185 }]
    did-server   = [{ route = "did-server", port = 9876 }]
  }

  ghcr_images = toset(["dashboard", "identityhub", "controlplane", "dataplane"])

  service_desired_counts = {
    postgres     = 1
    vault        = 1
    did-server   = 0
    dashboard    = 0
    identityhub  = 0
    controlplane = 0
    dataplane    = 0
  }

  autoscaled_routes = {
    did-server   = "did-server"
    dashboard    = "dashboard"
    identityhub  = "credentials"
    controlplane = "dsp"
    dataplane    = "data"
  }
}

resource "aws_security_group" "ecs_tasks_sg" {
  name        = "pilots-ecs-tasks-sg"
  description = "Allow traffic from ALB to ECS services"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port       = 7091
    to_port         = 7091
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port       = 7093
    to_port         = 7093
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port       = 9876
    to_port         = 9876
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port       = 19194
    to_port         = 19194
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port       = 38185
    to_port         = 38185
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/pilots-${var.environment}"
  retention_in_days = 30
}

resource "aws_security_group" "efs_sg" {
  name        = "pilots-efs-sg"
  description = "Allow ECS tasks to mount EFS"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_file_system" "pilots" {
  creation_token = "pilots-connector-${var.environment}"

  tags = {
    Name        = "pilots-connector-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_efs_access_point" "postgres_data" {
  file_system_id = aws_efs_file_system.pilots.id

  posix_user {
    gid = 999
    uid = 999
  }

  root_directory {
    path = "/postgres-data"
    creation_info {
      owner_gid   = 999
      owner_uid   = 999
      permissions = "0750"
    }
  }
}

resource "aws_efs_mount_target" "pilots" {
  for_each = toset(data.aws_subnets.default.ids)

  file_system_id  = aws_efs_file_system.pilots.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs_sg.id]
}

resource "aws_iam_role" "ecs_task_execution" {
  name = "pilots-ecs-task-execution-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_secret_access" {
  name = "pilots-ecs-ghcr-access-${var.environment}"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "kms:Decrypt"
        ]
        Resource = var.ghcr_credentials_secret_arn == "" ? "*" : var.ghcr_credentials_secret_arn
      }
    ]
  })
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

  dynamic "volume" {
    for_each = each.key == "postgres" ? [1] : []
    content {
      name = "postgres-data"
      efs_volume_configuration {
        file_system_id     = aws_efs_file_system.pilots.id
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = aws_efs_access_point.postgres_data.id
          iam             = "DISABLED"
        }
      }
    }
  }

  container_definitions = jsonencode([
    merge(
      {
        name      = each.key
        image     = each.value.image
        essential = true
        portMappings = [
          {
            containerPort = each.value.container_port
            protocol      = "tcp"
          }
        ]
        environment = each.value.environment
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

  depends_on = [
    aws_lb_listener.https,
    aws_iam_role_policy_attachment.ecs_task_execution_managed,
    aws_efs_mount_target.pilots
  ]
}

resource "aws_appautoscaling_target" "ecs_services" {
  for_each = local.autoscaled_routes

  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.pilots.name}/${aws_ecs_service.services[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 0
  max_capacity       = 1
}

resource "aws_appautoscaling_policy" "ecs_request_target_tracking" {
  for_each = local.autoscaled_routes

  name               = "pilots-${each.key}-requests"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_services[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_services[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_services[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 1
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.pilots_alb.arn_suffix}/${aws_lb_target_group.services[each.value].arn_suffix}"
    }
  }
}