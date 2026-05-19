output "service_name" {
  value = aws_ecs_service.this.name
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.this.arn
}

output "task_definition_family" {
  value = aws_ecs_task_definition.this.family
}

output "cloudmap_service_arn" {
  value = aws_service_discovery_service.this.arn
}

output "cloudmap_dns_name" {
  description = "Internal DNS name (resolvable via CloudMap from other tasks in the same namespace)."
  value       = "${var.name}.${var.namespace_name}"
}
