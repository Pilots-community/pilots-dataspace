output "route53_nameservers" {
  description = "Add these as NS records at the registrar for the configured root_domain. ACM validation blocks until this is done."
  value       = module.edge.nameservers
}

output "alb_dns_name" {
  description = "Underlying ALB DNS name. The apex A-alias to root_domain is created automatically."
  value       = module.edge.alb_dns_name
}

output "participant_did" {
  value = local.participant_did
}

output "issuer_did" {
  value = local.issuer_did
}

output "dashboard_url" {
  value = "https://${var.root_domain}/"
}

output "service_urls" {
  description = "Endpoints that peers and operators hit. Operator-only (mgmt/identity) ports are SG-restricted to var.mgmt_cidrs."
  value = {
    dashboard       = "https://${var.root_domain}/"
    credentials_api = "https://${var.root_domain}:7091/api/credentials"
    identity_api    = "https://${var.root_domain}:7092/api/identity"
    did_api         = "https://${var.root_domain}:7093/"
    issuer_did_doc  = "https://${var.root_domain}:9876/.well-known/did.json"
    mgmt_api        = "https://${var.root_domain}:19193/management"
    dsp_protocol    = "https://${var.root_domain}:19194/protocol"
    data_public     = "https://${var.root_domain}:38185/public"
  }
}

output "rds_endpoint" {
  value = "${module.rds.address}:${module.rds.port}"
}

output "vault_root_token_secret_arn" {
  description = "Read with: aws secretsmanager get-secret-value --secret-id <arn> --query SecretString --output text"
  value       = module.vault.root_token_secret_arn
}

output "db_password_secret_arn" {
  value = module.rds.db_password_secret_arn
}

output "rds_credentials_secret_arn" {
  description = "JSON blob with username/password/host/port/dbname for tooling (Bruno, psql wrappers)."
  value       = module.rds.rds_credentials_secret_arn
}

output "db_seeder_run_command" {
  description = "Copy/paste to create the identityhub + dataplane databases."
  value       = module.db_seeder.run_command
}

output "seeder_run_command" {
  description = "Copy/paste to render did.json into EFS. Required before peers can resolve the issuer DID."
  value       = module.seeder.run_command
}

output "ecs_cluster_name" {
  value = module.ecs_cluster.cluster_name
}

output "log_group_name" {
  value = module.ecs_cluster.log_group_name
}
