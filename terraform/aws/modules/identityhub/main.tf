locals {
  rendered_config = templatefile("${path.module}/templates/identityhub.properties.tftpl", {
    root_domain = var.root_domain
    rds_host    = var.rds_host
    rds_port    = var.rds_port
    db_username = var.db_username
    vault_dns   = var.vault_dns
  })
}

resource "aws_secretsmanager_secret" "config" {
  name                    = "${var.name_prefix}-identityhub-config"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "config" {
  secret_id     = aws_secretsmanager_secret.config.id
  secret_string = local.rendered_config
}

module "service" {
  source = "../ecs-service"

  name               = "identityhub"
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

  container_ports = [7090, 7091, 7092, 7093, 7095, 7096]

  secrets = [
    { name = "EDC_CONFIG", valueFrom = aws_secretsmanager_secret.config.arn },
    { name = "DB_PASSWORD", valueFrom = var.db_password_secret_arn },
    { name = "VAULT_TOKEN", valueFrom = var.vault_token_secret_arn },
  ]

  # Materialise the .properties file from the env var at startup, then exec the JAR.
  # Two non-obvious steps in the pipeline:
  #   - mkdir /app/config: the upstream EDC image has no /app/config dir, so
  #     sh exits 1 on the redirect without it.
  #   - sed pre-substitutes the $${DB_PASSWORD} / $${VAULT_TOKEN} placeholders
  #     with the real env-var values before EDC reads the file. EDC's properties
  #     loader resolves ${key} against OTHER keys in the same config — it does
  #     NOT pull from process env. Without this, the literal strings would be
  #     sent verbatim to Postgres / Vault and auth fails.
  command = [
    "sh", "-c",
    "mkdir -p /app/config && printf '%s\\n' \"$EDC_CONFIG\" | sed -e 's|$${DB_PASSWORD}|'\"$DB_PASSWORD\"'|g' -e 's|$${VAULT_TOKEN}|'\"$VAULT_TOKEN\"'|g' > /app/config/identityhub-connector.properties && exec java -Djava.security.egd=file:/dev/urandom -Dedc.fs.config=/app/config/identityhub-connector.properties -jar identityhub.jar",
  ]

  healthcheck = {
    command      = ["CMD-SHELL", "curl --fail http://localhost:7090/api/check/health || exit 1"]
    interval     = 30
    timeout      = 5
    retries      = 5
    start_period = 120
  }

  alb_target_groups = var.alb_target_groups
}
