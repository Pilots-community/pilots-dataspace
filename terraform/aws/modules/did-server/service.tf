module "service" {
  source = "../ecs-service"

  name               = "did-server"
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
  container_ports = [9876]

  secrets = [
    {
      name      = "NGINX_CONF"
      valueFrom = aws_secretsmanager_secret.nginx_conf.arn
    },
  ]

  mounts = [
    {
      source_volume   = "did-content"
      file_system_id  = aws_efs_file_system.this.id
      access_point_id = aws_efs_access_point.this.id
      container_path  = "/usr/share/nginx/html/issuer"
      read_only       = true
    },
  ]

  # Materialise nginx.conf from the env var, then exec nginx in foreground.
  command = [
    "sh", "-c",
    "printf '%s\\n' \"$NGINX_CONF\" > /etc/nginx/conf.d/default.conf && exec nginx -g 'daemon off;'",
  ]

  # Health check returns 404 before the seeder runs, 200 after. Match either
  # so ECS doesn't mark the task unhealthy during the bootstrap window.
  healthcheck = {
    command      = ["CMD-SHELL", "wget --spider -q http://127.0.0.1:9876/issuer/did.json 2>/dev/null || nc -z 127.0.0.1 9876"]
    interval     = 30
    timeout      = 5
    retries      = 5
    start_period = 30
  }

  alb_target_groups = [
    { target_group_arn = var.alb_target_group_arn, container_port = 9876 },
  ]

  depends_on = [aws_efs_mount_target.this]
}
