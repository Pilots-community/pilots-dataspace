locals {
  rendered_config = templatefile("${path.module}/templates/controlplane.properties.tftpl", {
    root_domain     = var.root_domain
    rds_host        = var.rds_host
    rds_port        = var.rds_port
    db_username     = var.db_username
    vault_dns       = var.vault_dns
    identityhub_dns = var.identityhub_dns
  })
}

resource "aws_secretsmanager_secret" "config" {
  name                    = "${var.name_prefix}-controlplane-config"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "config" {
  secret_id     = aws_secretsmanager_secret.config.id
  secret_string = local.rendered_config
}

module "service" {
  source = "../ecs-service"

  name               = "controlplane"
  name_prefix        = var.name_prefix
  cluster_id         = var.cluster_id
  namespace_id       = var.namespace_id
  namespace_name     = var.namespace_name
  execution_role_arn = var.execution_role_arn
  task_role_arn      = var.task_role_arn
  log_group_name     = var.log_group_name
  region             = var.region
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids

  image                       = var.image
  ghcr_credentials_secret_arn = var.ghcr_credentials_secret_arn
  cpu                         = var.cpu
  memory                      = var.memory

  container_ports = [18181, 19192, 19193, 19194]

  secrets = [
    { name = "EDC_CONFIG", valueFrom = aws_secretsmanager_secret.config.arn },
    { name = "DB_PASSWORD", valueFrom = var.db_password_secret_arn },
    { name = "VAULT_TOKEN", valueFrom = var.vault_token_secret_arn },
  ]

  # `unset WEB_HTTP_PORT WEB_HTTP_PATH` mirrors the local docker-compose
  # workaround: ECS may set these from its own conventions, and they'd
  # override the values in our .properties file.
  command = [
    "sh", "-c",
    "unset WEB_HTTP_PORT WEB_HTTP_PATH && printf '%s\\n' \"$EDC_CONFIG\" > /app/config/controlplane-connector.properties && exec java -Djava.security.egd=file:/dev/urandom -Dedc.fs.config=/app/config/controlplane-connector.properties -jar edc-controlplane.jar",
  ]

  healthcheck = {
    command      = ["CMD-SHELL", "curl --fail http://localhost:18181/api/check/health || exit 1"]
    interval     = 30
    timeout      = 5
    retries      = 5
    start_period = 180
  }

  alb_target_groups = var.alb_target_groups
}
