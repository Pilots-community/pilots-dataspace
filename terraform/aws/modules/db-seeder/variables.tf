variable "name_prefix" {
  type = string
}

variable "cluster_id" {
  type = string
}

variable "cluster_name" {
  description = "Cluster name (used in the run-task command emitted as output)."
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
  description = "Subnets the one-shot task runs in. Public subnet recommended (the task needs to reach Secrets Manager and the public RDS endpoint via VPC routing)."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups for the task ENI. Must include a group with egress to RDS."
  type        = list(string)
}

variable "rds_host" {
  type = string
}

variable "rds_port" {
  type    = number
  default = 5432
}

variable "db_username" {
  type = string
}

variable "db_password_secret_arn" {
  type = string
}

variable "databases_to_create" {
  description = "Databases the seeder ensures exist (controlplane is created by RDS at init)."
  type        = list(string)
  default     = ["dataplane", "identityhub"]
}
