variable "name_prefix" {
  description = "Prefix used in the dashboard name."
  type        = string
}

variable "region" {
  description = "AWS region (used to scope each CloudWatch metric widget)."
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name."
  type        = string
}

variable "service_names" {
  description = "ECS service names whose RunningTaskCount + DesiredTaskCount should be plotted."
  type        = list(string)
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix (LoadBalancer dimension for AWS/ApplicationELB metrics)."
  type        = string
}

variable "target_group_arn_suffixes" {
  description = "Map of TG name -> ARN suffix (TargetGroup dimension for HealthyHostCount per TG)."
  type        = map(string)
}

variable "rds_instance_identifier" {
  description = "RDS DBInstanceIdentifier (dimension for AWS/RDS metrics)."
  type        = string
}
