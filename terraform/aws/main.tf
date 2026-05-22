################################################################################
# Network — default VPC + security groups for ALB, ECS, RDS, EFS.
################################################################################
module "network" {
  source = "./modules/network"

  name_prefix = local.name_prefix
}

################################################################################
# RDS — single Postgres instance, three logical DBs (controlplane on init,
# identityhub + dataplane added by db_seeder).
################################################################################
module "rds" {
  source = "./modules/rds"

  name_prefix       = local.name_prefix
  environment       = var.environment
  username          = var.db_username
  instance_class    = var.db_instance_class
  subnet_ids        = module.network.subnet_ids
  security_group_id = module.network.rds_security_group_id
}

################################################################################
# Edge — ACM cert, Route53 zone + apex alias, single HTTPS listener on 443
# with path-based routing. All external traffic enters on 443 only.
# Priority values: lower = evaluated first (specific paths before wildcards).
################################################################################
locals {
  edge_routes = [
    # Dashboard: null path_patterns = listener default action (catches everything else)
    { name = "dashboard", target_port = 80, path_patterns = null, priority = null, health_path = "/", health_matcher = "200-399" },
    # IdentityHub — three APIs on three backend ports
    { name = "ih-credentials", target_port = 7091, path_patterns = ["/api/credentials/*"], priority = 10, health_path = "/api/credentials/v1/participants/foo", health_matcher = "200-499" },
    { name = "ih-identity", target_port = 7092, path_patterns = ["/api/identity/*"], priority = 20, health_path = "/api/identity/v1alpha/participants", health_matcher = "200-499" },
    { name = "ih-did", target_port = 7093, path_patterns = ["/.well-known/did.json"], priority = 5, health_path = "/.well-known/did.json", health_matcher = "200-499" },
    # Issuer DID: did:web:<domain>:issuer resolves to https://<domain>/issuer/did.json
    { name = "did-server", target_port = 9876, path_patterns = ["/issuer/did.json"], priority = 6, health_path = "/issuer/did.json", health_matcher = "200,404" },
    # Control plane
    { name = "cp-mgmt", target_port = 19193, path_patterns = ["/management/*"], priority = 30, health_path = "/management/v3/secrets", health_matcher = "200-499" },
    { name = "cp-dsp", target_port = 19194, path_patterns = ["/protocol/*"], priority = 40, health_path = "/protocol", health_matcher = "200-499" },
    # Data plane
    { name = "dp-public", target_port = 38185, path_patterns = ["/public/*"], priority = 50, health_path = "/public", health_matcher = "200-499" },
  ]
}

module "edge" {
  source = "./modules/edge"

  name_prefix           = local.name_prefix
  root_domain           = var.root_domain
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.subnet_ids
  alb_security_group_id = module.network.alb_security_group_id
  routes                = local.edge_routes
}

################################################################################
# ECS cluster — Fargate, CloudMap namespace, split execution/task IAM roles,
# CloudWatch log group shared by every service.
################################################################################
module "ecs_cluster" {
  source = "./modules/ecs-cluster"

  name_prefix                 = local.name_prefix
  environment                 = var.environment
  vpc_id                      = module.network.vpc_id
  ghcr_credentials_secret_arn = var.ghcr_credentials_secret_arn
}

################################################################################
# Common task-execution wiring shared by every service module.
################################################################################
locals {
  task_common = {
    cluster_id         = module.ecs_cluster.cluster_id
    namespace_id       = module.ecs_cluster.namespace_id
    namespace_name     = module.ecs_cluster.namespace_name
    execution_role_arn = module.ecs_cluster.execution_role_arn
    task_role_arn      = module.ecs_cluster.task_role_arn
    log_group_name     = module.ecs_cluster.log_group_name
    region             = var.region
    subnet_ids         = module.network.subnet_ids
    security_group_ids = [module.network.ecs_tasks_security_group_id]
  }

  image_registry = "ghcr.io/pilots-community/pilots-dataspace"
}

################################################################################
# Vault — dev mode, in-memory. Re-seed via scripts/seed-aws.sh on restart.
################################################################################
module "vault" {
  source = "./modules/vault"

  name_prefix        = local.name_prefix
  cluster_id         = local.task_common.cluster_id
  namespace_id       = local.task_common.namespace_id
  namespace_name     = local.task_common.namespace_name
  execution_role_arn = local.task_common.execution_role_arn
  task_role_arn      = local.task_common.task_role_arn
  log_group_name     = local.task_common.log_group_name
  region             = local.task_common.region
  subnet_ids         = local.task_common.subnet_ids
  security_group_ids = local.task_common.security_group_ids
}

################################################################################
# DID server — nginx + EFS shared with the seeder task that writes did.json.
################################################################################
module "did_server" {
  source = "./modules/did-server"

  name_prefix           = local.name_prefix
  cluster_id            = local.task_common.cluster_id
  namespace_id          = local.task_common.namespace_id
  namespace_name        = local.task_common.namespace_name
  execution_role_arn    = local.task_common.execution_role_arn
  task_role_arn         = local.task_common.task_role_arn
  log_group_name        = local.task_common.log_group_name
  region                = local.task_common.region
  subnet_ids            = local.task_common.subnet_ids
  security_group_ids    = local.task_common.security_group_ids
  efs_security_group_id = module.network.efs_security_group_id

  alb_target_group_arn = module.edge.target_group_arns["did-server"]
}

################################################################################
# IdentityHub — must come up before controlplane (controlplane fetches STS
# tokens from identityhub.pilots.internal:7096). EDC apps retry on failure
# so first-boot races resolve themselves within a couple of container restarts.
################################################################################
module "identityhub" {
  source = "./modules/identityhub"

  name_prefix                 = local.name_prefix
  cluster_id                  = local.task_common.cluster_id
  namespace_id                = local.task_common.namespace_id
  namespace_name              = local.task_common.namespace_name
  execution_role_arn          = local.task_common.execution_role_arn
  task_role_arn               = local.task_common.task_role_arn
  log_group_name              = local.task_common.log_group_name
  region                      = local.task_common.region
  subnet_ids                  = local.task_common.subnet_ids
  security_group_ids          = local.task_common.security_group_ids
  image                       = "${local.image_registry}/identityhub:${var.image_tag}"
  ghcr_credentials_secret_arn = var.ghcr_credentials_secret_arn
  cpu                         = var.ecs_cpu
  memory                      = var.ecs_memory

  root_domain            = var.root_domain
  rds_host               = module.rds.address
  rds_port               = module.rds.port
  db_username            = module.rds.username
  db_password_secret_arn = module.rds.db_password_secret_arn
  vault_dns              = module.vault.dns_name
  vault_token_secret_arn = module.vault.root_token_secret_arn

  alb_target_groups = [
    { target_group_arn = module.edge.target_group_arns["ih-credentials"], container_port = 7091 },
    { target_group_arn = module.edge.target_group_arns["ih-identity"], container_port = 7092 },
    { target_group_arn = module.edge.target_group_arns["ih-did"], container_port = 7093 },
  ]
}

################################################################################
# Control plane.
################################################################################
module "controlplane" {
  source = "./modules/controlplane"

  name_prefix                 = local.name_prefix
  cluster_id                  = local.task_common.cluster_id
  namespace_id                = local.task_common.namespace_id
  namespace_name              = local.task_common.namespace_name
  execution_role_arn          = local.task_common.execution_role_arn
  task_role_arn               = local.task_common.task_role_arn
  log_group_name              = local.task_common.log_group_name
  region                      = local.task_common.region
  subnet_ids                  = local.task_common.subnet_ids
  security_group_ids          = local.task_common.security_group_ids
  image                       = "${local.image_registry}/controlplane:${var.image_tag}"
  ghcr_credentials_secret_arn = var.ghcr_credentials_secret_arn
  cpu                         = var.ecs_cpu
  memory                      = var.ecs_memory

  root_domain            = var.root_domain
  rds_host               = module.rds.address
  rds_port               = module.rds.port
  db_username            = module.rds.username
  db_password_secret_arn = module.rds.db_password_secret_arn
  vault_dns              = module.vault.dns_name
  vault_token_secret_arn = module.vault.root_token_secret_arn
  identityhub_dns        = module.identityhub.dns_name

  alb_target_groups = [
    { target_group_arn = module.edge.target_group_arns["cp-mgmt"], container_port = 19193 },
    { target_group_arn = module.edge.target_group_arns["cp-dsp"], container_port = 19194 },
  ]
}

################################################################################
# Data plane.
################################################################################
module "dataplane" {
  source = "./modules/dataplane"

  name_prefix                 = local.name_prefix
  cluster_id                  = local.task_common.cluster_id
  namespace_id                = local.task_common.namespace_id
  namespace_name              = local.task_common.namespace_name
  execution_role_arn          = local.task_common.execution_role_arn
  task_role_arn               = local.task_common.task_role_arn
  log_group_name              = local.task_common.log_group_name
  region                      = local.task_common.region
  subnet_ids                  = local.task_common.subnet_ids
  security_group_ids          = local.task_common.security_group_ids
  image                       = "${local.image_registry}/dataplane:${var.image_tag}"
  ghcr_credentials_secret_arn = var.ghcr_credentials_secret_arn
  cpu                         = var.ecs_cpu
  memory                      = var.ecs_memory

  root_domain            = var.root_domain
  rds_host               = module.rds.address
  rds_port               = module.rds.port
  db_username            = module.rds.username
  db_password_secret_arn = module.rds.db_password_secret_arn
  vault_dns              = module.vault.dns_name
  vault_token_secret_arn = module.vault.root_token_secret_arn
  controlplane_dns       = module.controlplane.dns_name
  private_key_secret_arn = var.dataplane_private_key_secret_arn
  public_key_secret_arn  = var.dataplane_public_key_secret_arn

  alb_target_groups = [
    { target_group_arn = module.edge.target_group_arns["dp-public"], container_port = 38185 },
  ]
}

################################################################################
# Dashboard — operator UI served at the apex (/) as the ALB default action.
################################################################################
module "dashboard" {
  source = "./modules/dashboard"

  name_prefix                 = local.name_prefix
  cluster_id                  = local.task_common.cluster_id
  namespace_id                = local.task_common.namespace_id
  namespace_name              = local.task_common.namespace_name
  execution_role_arn          = local.task_common.execution_role_arn
  task_role_arn               = local.task_common.task_role_arn
  log_group_name              = local.task_common.log_group_name
  region                      = local.task_common.region
  subnet_ids                  = local.task_common.subnet_ids
  security_group_ids          = local.task_common.security_group_ids
  image                       = "${local.image_registry}/dashboard:${var.image_tag}"
  ghcr_credentials_secret_arn = var.ghcr_credentials_secret_arn
  cpu                         = var.ecs_cpu
  memory                      = var.ecs_memory

  controlplane_dns = module.controlplane.dns_name
  dataplane_dns    = module.dataplane.dns_name
  identityhub_dns  = module.identityhub.dns_name

  alb_target_groups = [
    { target_group_arn = module.edge.target_group_arns["dashboard"], container_port = 80 },
  ]
}

################################################################################
# One-shot tasks: db schema bootstrap + did.json render.
################################################################################
module "db_seeder" {
  source = "./modules/db-seeder"

  name_prefix            = local.name_prefix
  cluster_id             = local.task_common.cluster_id
  cluster_name           = module.ecs_cluster.cluster_name
  execution_role_arn     = local.task_common.execution_role_arn
  task_role_arn          = local.task_common.task_role_arn
  log_group_name         = local.task_common.log_group_name
  region                 = local.task_common.region
  subnet_ids             = local.task_common.subnet_ids
  security_group_ids     = local.task_common.security_group_ids
  rds_host               = module.rds.address
  rds_port               = module.rds.port
  db_username            = module.rds.username
  db_password_secret_arn = module.rds.db_password_secret_arn
}

module "seeder" {
  source = "./modules/seeder"

  name_prefix                   = local.name_prefix
  cluster_id                    = local.task_common.cluster_id
  cluster_name                  = module.ecs_cluster.cluster_name
  execution_role_arn            = local.task_common.execution_role_arn
  task_role_arn                 = local.task_common.task_role_arn
  log_group_name                = local.task_common.log_group_name
  region                        = local.task_common.region
  subnet_ids                    = local.task_common.subnet_ids
  security_group_ids            = local.task_common.security_group_ids
  root_domain                   = var.root_domain
  issuer_private_key_secret_arn = var.issuer_private_key_secret_arn
  efs_file_system_id            = module.did_server.efs_file_system_id
  efs_access_point_id           = module.did_server.efs_access_point_id
}
