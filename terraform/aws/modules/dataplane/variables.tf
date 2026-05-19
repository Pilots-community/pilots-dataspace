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
  description = "Data plane container image."
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
  type = string
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
  type = string
}

variable "vault_dns" {
  type = string
}

variable "vault_token_secret_arn" {
  type = string
}

variable "controlplane_dns" {
  description = "Internal DNS name of the controlplane service (provides the dataplane selector endpoint on :19192)."
  type        = string
}

variable "private_key_secret_arn" {
  description = "Secrets Manager ARN holding the EDR-signing private key PEM. Written to /tmp/private-key.pem at container start."
  type        = string
}

variable "public_key_secret_arn" {
  description = "Secrets Manager ARN holding the EDR-signing public key PEM."
  type        = string
}

variable "alb_target_groups" {
  description = "List of {target_group_arn, container_port}. Expect one: data (38185)."
  type = list(object({
    target_group_arn = string
    container_port   = number
  }))
}
