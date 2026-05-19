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
  description = "IdentityHub container image."
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

variable "root_domain" {
  description = "Public domain (used for edc.hostname and DID composition)."
  type        = string
}

variable "rds_host" {
  type = string
}

variable "rds_port" {
  type = number
}

variable "db_username" {
  type = string
}

variable "db_password_secret_arn" {
  description = "Secrets Manager ARN for the RDS password. Injected as $DB_PASSWORD."
  type        = string
}

variable "vault_dns" {
  description = "Internal DNS name of the Vault service (e.g. vault.pilots.internal)."
  type        = string
}

variable "vault_token_secret_arn" {
  description = "Secrets Manager ARN for the Vault root token. Injected as $VAULT_TOKEN."
  type        = string
}

variable "alb_target_groups" {
  description = "List of {target_group_arn, container_port} attachments. Expect three: credentials (7091), identity (7092), did (7093)."
  type = list(object({
    target_group_arn = string
    container_port   = number
  }))
}
