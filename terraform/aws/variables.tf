variable "environment" {
  type    = string
  default = "dev"
}

variable "region" {
  type    = string
  default = "eu-west-3"
}

variable "root_domain" {
  description = "The root domain for the pilots infrastructure"
  type        = string
  default     = "pilots.t-mining.ma-de.be"
}

variable "ghcr_credentials_secret_arn" {
  description = "Secrets Manager ARN containing GHCR Docker credentials (username/password or dockerconfigjson)"
  type        = string
  default     = ""
}

variable "image_tag" {
  description = "Container image tag deployed for all pilots services"
  type        = string
  default     = "latest"
}

variable "ecs_cpu" {
  description = "Default ECS task CPU units"
  type        = number
  default     = 256
}

variable "ecs_memory" {
  description = "Default ECS task memory in MiB"
  type        = number
  default     = 512
}

variable "db_username" {
  description = "Username for the RDS instance"
  type        = string
  default     = "edc"
}

variable "db_password" {
  description = "Password for the RDS instance (Initial value, managed in Secrets Manager/Console after creation)"
  type        = string
  sensitive   = true
  default     = "edcedcedc"
}

variable "db_instance_class" {
  description = "The instance type of the RDS instance"
  type        = string
  default     = "db.t4g.micro"
}