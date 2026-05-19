# Vault runs in dev mode: in-memory only, intentionally. The seed step
# populates STS client secrets via EDC's /management/v3/secrets API after
# every container restart. Production hardening (raft storage on EFS, KMS
# auto-unseal) is a follow-up listed in the plan.

resource "random_password" "root_token" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "root_token" {
  name                    = "${var.name_prefix}-vault-root-token"
  description             = "Dev-mode Vault root token. Rotated by destroying this secret + restarting the vault task."
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "root_token" {
  secret_id     = aws_secretsmanager_secret.root_token.id
  secret_string = random_password.root_token.result
}

module "service" {
  source = "../ecs-service"

  name               = "vault"
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

  image           = var.image
  cpu             = var.cpu
  memory          = var.memory
  container_ports = [8200]

  # VAULT_DEV_ROOT_TOKEN_ID gets read by the vault dev-mode init at startup.
  secrets = [
    {
      name      = "VAULT_DEV_ROOT_TOKEN_ID"
      valueFrom = aws_secretsmanager_secret.root_token.arn
    },
  ]

  environment = [
    { name = "VAULT_DEV_LISTEN_ADDRESS", value = "0.0.0.0:8200" },
    { name = "VAULT_ADDR", value = "http://127.0.0.1:8200" },
  ]

  # Default entrypoint of the vault image runs `vault server -dev` when
  # VAULT_DEV_ROOT_TOKEN_ID is set; no command override needed.

  healthcheck = {
    command      = ["CMD", "vault", "status"]
    interval     = 30
    timeout      = 5
    retries      = 5
    start_period = 30
  }
}
