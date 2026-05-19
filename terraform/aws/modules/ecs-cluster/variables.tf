variable "name_prefix" {
  description = "Prefix for cluster, role and log-group names."
  type        = string
}

variable "environment" {
  description = "Environment tag."
  type        = string
}

variable "vpc_id" {
  description = "VPC for the service-discovery namespace."
  type        = string
}

variable "namespace_name" {
  description = "Private DNS namespace for inter-service traffic."
  type        = string
  default     = "pilots.internal"
}

variable "ghcr_credentials_secret_arn" {
  description = "Optional GHCR pull-credentials secret ARN. Granted to the execution role for image pulls."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the per-cluster log group."
  type        = number
  default     = 30
}
