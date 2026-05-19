module "service" {
  source = "../ecs-service"

  name               = "dashboard"
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

  container_ports = [80]

  # Dashboard's docker entrypoint runs envsubst on nginx.conf.template with
  # these env vars at startup. See dashboard/Dockerfile.
  environment = [
    { name = "CP_HOST", value = var.controlplane_dns },
    { name = "CP_MGMT_PORT", value = "19193" },
    { name = "CP_HEALTH_PORT", value = "18181" },
    { name = "DP_HOST", value = var.dataplane_dns },
    { name = "DP_HEALTH_PORT", value = "38181" },
    { name = "DP_PUBLIC_PORT", value = "38185" },
    { name = "IH_HOST", value = var.identityhub_dns },
    { name = "IH_HEALTH_PORT", value = "7090" },
  ]

  healthcheck = {
    command      = ["CMD-SHELL", "curl --fail http://localhost/ || exit 1"]
    interval     = 30
    timeout      = 5
    retries      = 5
    start_period = 30
  }

  alb_target_groups = var.alb_target_groups
}
