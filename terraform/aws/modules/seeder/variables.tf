variable "name_prefix" {
  type = string
}

variable "cluster_id" {
  type = string
}

variable "cluster_name" {
  description = "ECS cluster name (used in the emitted run-task command)."
  type        = string
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
  description = "Security groups for the seeder task ENI (must permit egress to EFS mount targets on 2049)."
  type        = list(string)
}

variable "root_domain" {
  description = "Public root domain. Used to compose the issuer DID written into did.json."
  type        = string
}

variable "issuer_private_key_secret_arn" {
  description = "Secrets Manager ARN holding the issuer PEM private key (raw PEM)."
  type        = string
}

variable "efs_file_system_id" {
  description = "EFS filesystem id (shared with did-server)."
  type        = string
}

variable "efs_access_point_id" {
  description = "EFS access point id (shared with did-server, posix uid/gid 101)."
  type        = string
}
