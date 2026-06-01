variable "name_prefix" {
  type = string
}

variable "cluster_id" {
  type = string
}

variable "namespace_id" {
  type = string
}

variable "namespace_name" {
  type = string
}

variable "execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "log_group_name" {
  type = string
}

variable "region" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "image" {
  description = "Dashboard container image."
  type        = string
}

variable "ghcr_credentials_secret_arn" {
  type    = string
  default = ""
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "controlplane_dns" {
  description = "Internal DNS name of controlplane (dashboard nginx proxies management + health endpoints here)."
  type        = string
}

variable "dataplane_dns" {
  description = "Internal DNS name of dataplane (dashboard nginx proxies public EDR fetches here)."
  type        = string
}

variable "identityhub_dns" {
  description = "Internal DNS name of identityhub (dashboard nginx proxies health checks here)."
  type        = string
}

variable "alb_target_groups" {
  description = "List of {target_group_arn, container_port}. Expect one: dashboard (80)."
  type = list(object({
    target_group_arn = string
    container_port   = number
  }))
}
