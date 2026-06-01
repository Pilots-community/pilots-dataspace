output "dns_name" {
  description = "Internal DNS name (e.g. vault.pilots.internal)."
  value       = module.service.cloudmap_dns_name
}

output "url" {
  description = "Internal URL for EDC services (http://vault.pilots.internal:8200)."
  value       = "http://${module.service.cloudmap_dns_name}:8200"
}

output "root_token_secret_arn" {
  value = aws_secretsmanager_secret.root_token.arn
}

output "service_name" {
  value = module.service.service_name
}
