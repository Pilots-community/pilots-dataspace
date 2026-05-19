variable "name" {
  description = "Service short name (used in task family, service name, log stream prefix, CloudMap A record)."
  type        = string
}

variable "name_prefix" {
  description = "Cluster/environment prefix (e.g. pilots-dev). Combined with `name` to form unique resource names."
  type        = string
}

variable "cluster_id" {
  description = "ECS cluster id."
  type        = string
}

variable "namespace_id" {
  description = "CloudMap private DNS namespace id for service discovery."
  type        = string
}

variable "namespace_name" {
  description = "CloudMap private DNS namespace name (used to compose the FQDN output)."
  type        = string
}

variable "execution_role_arn" {
  description = "ECS task execution role (pulls images, writes logs, materialises secrets)."
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role (used by the application at runtime)."
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group. Service uses `name` as the stream prefix."
  type        = string
}

variable "region" {
  description = "AWS region (passed into the awslogs driver)."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the service ENIs."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups for the service ENIs."
  type        = list(string)
}

variable "image" {
  description = "Full container image URI."
  type        = string
}

variable "cpu" {
  description = "Fargate CPU units."
  type        = number
}

variable "memory" {
  description = "Fargate memory (MiB)."
  type        = number
}

variable "container_ports" {
  description = "All ports the container exposes (used for portMappings — ALB attachment is a subset)."
  type        = list(number)
}

variable "environment" {
  description = "Plain environment variables."
  type        = list(object({ name = string, value = string }))
  default     = []
}

variable "secrets" {
  description = "Secret-backed environment variables ({name, valueFrom})."
  type        = list(object({ name = string, valueFrom = string }))
  default     = []
}

variable "mounts" {
  description = "EFS mounts. Each becomes both a top-level volume and a mountPoint."
  type = list(object({
    source_volume   = string
    file_system_id  = string
    access_point_id = string
    container_path  = string
    read_only       = bool
  }))
  default = []
}

variable "command" {
  description = "Container command (overrides image default)."
  type        = list(string)
  default     = null
}

variable "entrypoint" {
  description = "Container entrypoint."
  type        = list(string)
  default     = null
}

variable "healthcheck" {
  description = "Container HEALTHCHECK (used by ECS to gate `RUNNING -> HEALTHY`)."
  type = object({
    command      = list(string)
    interval     = number
    timeout      = number
    retries      = number
    start_period = number
  })
  default = null
}

variable "alb_target_groups" {
  description = "ALB attachments — each entry registers this service's `container_port` against the given TG."
  type = list(object({
    target_group_arn = string
    container_port   = number
  }))
  default = []
}

variable "ghcr_credentials_secret_arn" {
  description = "Optional GHCR pull-creds secret ARN. Adds repositoryCredentials to the container definition."
  type        = string
  default     = ""
}

variable "desired_count" {
  description = "Number of tasks to run."
  type        = number
  default     = 1
}

variable "assign_public_ip" {
  description = "Whether the task ENI gets a public IP (needed for GHCR pulls in the default VPC, which has no NAT)."
  type        = bool
  default     = true
}

variable "enable_execute_command" {
  description = "Allow `aws ecs execute-command` for debugging."
  type        = bool
  default     = true
}

variable "platform_version" {
  description = "Fargate platform version (1.4.0+ required for EFS)."
  type        = string
  default     = "1.4.0"
}
