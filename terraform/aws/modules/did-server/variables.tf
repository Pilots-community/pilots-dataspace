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
  description = "CloudMap namespace name."
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
  description = "Subnets for the task ENI + EFS mount targets."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups for the task ENI."
  type        = list(string)
}

variable "efs_security_group_id" {
  description = "Security group attached to EFS mount targets (controls NFS access)."
  type        = string
}

variable "image" {
  description = "Container image."
  type        = string
  default     = "nginx:alpine"
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

variable "alb_target_group_arn" {
  description = "ALB target group ARN to attach to (did-server listener on 9876)."
  type        = string
}
