output "dns_name" {
  description = "CloudMap DNS name (e.g. identityhub.pilots.internal). Used by controlplane for the STS token URL."
  value       = module.service.cloudmap_dns_name
}

output "service_name" {
  value = module.service.service_name
}
