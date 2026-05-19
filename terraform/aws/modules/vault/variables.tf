variable "name_prefix" {
  description = "Cluster/environment prefix."
  type        = string
}

variable "cluster_id" {
  description = "ECS cluster id."
  type        = string
}

variable "namespace_id" {
  description = "CloudMap namespace id."
  type        = string
}

variable "namespace_name" {
  description = "CloudMap namespace name (e.g. pilots.internal)."
  type        = string
}

variable "execution_role_arn" {
  description = "ECS task execution role."
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role."
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the vault task ENI."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups for the vault task ENI."
  type        = list(string)
}

variable "image" {
  description = "Vault container image."
  type        = string
  default     = "hashicorp/vault:1.15"
}

variable "cpu" {
  description = "Fargate CPU units."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate memory (MiB)."
  type        = number
  default     = 512
}
