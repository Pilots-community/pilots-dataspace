locals {
  rendered_config = templatefile("${path.module}/templates/dataplane.properties.tftpl", {
    root_domain      = var.root_domain
    rds_host         = var.rds_host
    rds_port         = var.rds_port
    db_username      = var.db_username
    vault_dns        = var.vault_dns
    controlplane_dns = var.controlplane_dns
  })
}

resource "aws_secretsmanager_secret" "config" {
  name                    = "${var.name_prefix}-dataplane-config"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "config" {
  secret_id     = aws_secretsmanager_secret.config.id
  secret_string = local.rendered_config
}

module "service" {
  source = "../ecs-service"

  name               = "dataplane"
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

  container_ports = [38181, 38182, 38185]

  secrets = [
    { name = "EDC_CONFIG", valueFrom = aws_secretsmanager_secret.config.arn },
    { name = "DB_PASSWORD", valueFrom = var.db_password_secret_arn },
    { name = "VAULT_TOKEN", valueFrom = var.vault_token_secret_arn },
    { name = "EDC_DATAPLANE_PRIVATE_KEY", valueFrom = var.private_key_secret_arn },
    { name = "EDC_DATAPLANE_PUBLIC_KEY", valueFrom = var.public_key_secret_arn },
  ]

  # Pipeline steps, in order:
  #   - unset WEB_HTTP_PORT WEB_HTTP_PATH: ECS may set these from its own
  #     conventions and they'd override our .properties file.
  #   - mkdir /app/config: the upstream EDC image has no /app/config dir.
  #   - sed pre-substitutes $${DB_PASSWORD} / $${VAULT_TOKEN} with the real
  #     env-var values (EDC's properties loader doesn't resolve env vars from
  #     a file — without this, the literal placeholders reach Postgres/Vault).
  #   - Private/public PEMs go to /tmp (always exists), no mkdir needed and
  #     no placeholders to substitute.
  command = [
    "sh", "-c",
    "unset WEB_HTTP_PORT WEB_HTTP_PATH && mkdir -p /app/config && printf '%s\\n' \"$EDC_CONFIG\" | sed -e 's|$${DB_PASSWORD}|'\"$DB_PASSWORD\"'|g' -e 's|$${VAULT_TOKEN}|'\"$VAULT_TOKEN\"'|g' > /app/config/dataplane-connector.properties && printf '%s\\n' \"$EDC_DATAPLANE_PRIVATE_KEY\" > /tmp/private-key.pem && printf '%s\\n' \"$EDC_DATAPLANE_PUBLIC_KEY\" > /tmp/public-key.pem && exec java -Djava.security.egd=file:/dev/urandom -Dedc.fs.config=/app/config/dataplane-connector.properties -jar edc-dataplane.jar",
  ]

  healthcheck = {
    command      = ["CMD-SHELL", "curl --fail http://localhost:38181/api/check/health || exit 1"]
    interval     = 30
    timeout      = 5
    retries      = 5
    start_period = 180
  }

  alb_target_groups = var.alb_target_groups
}
