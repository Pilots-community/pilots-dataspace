output "efs_file_system_id" {
  description = "EFS filesystem id. The seeder module mounts the same filesystem RW to write did.json."
  value       = aws_efs_file_system.this.id
}

output "efs_access_point_id" {
  description = "EFS access point id (uid/gid 101). The seeder reuses this access point so files it writes are readable by nginx."
  value       = aws_efs_access_point.this.id
}

output "dns_name" {
  value = module.service.cloudmap_dns_name
}

output "service_name" {
  value = module.service.service_name
}
