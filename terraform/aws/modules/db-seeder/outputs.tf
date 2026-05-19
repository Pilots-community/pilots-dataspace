output "task_family" {
  value = aws_ecs_task_definition.this.family
}

output "run_command" {
  description = "Copy/paste shell command to run the seeder task. Reads STDIN nothing; pipes to bash."
  value       = <<-CMD
    aws ecs run-task \
      --cluster ${var.cluster_name} \
      --task-definition ${aws_ecs_task_definition.this.family} \
      --launch-type FARGATE \
      --platform-version 1.4.0 \
      --network-configuration 'awsvpcConfiguration={subnets=[${join(",", var.subnet_ids)}],securityGroups=[${join(",", var.security_group_ids)}],assignPublicIp=ENABLED}' \
      --region ${var.region}
  CMD
}
