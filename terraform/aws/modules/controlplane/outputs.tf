output "dns_name" {
  description = "CloudMap DNS name (e.g. controlplane.pilots.internal). Used by dataplane for the control API URL."
  value       = module.service.cloudmap_dns_name
}

output "service_name" {
  value = module.service.service_name
}
