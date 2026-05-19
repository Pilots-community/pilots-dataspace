variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "username" {
  description = "Master username."
  type        = string
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the DB subnet group."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group attached to the instance."
  type        = string
}

variable "initial_db_name" {
  description = "Database created at instance bootstrap. Other databases are created later by the db-seeder ECS task."
  type        = string
  default     = "controlplane"
}
