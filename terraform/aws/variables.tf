variable "environment" {
  description = "Environment name (used in resource names and tags)."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-3"
}

variable "root_domain" {
  description = "Root domain served by this deployment. A Route53 hosted zone is created for it; the registrar must delegate NS records."
  type        = string
}

variable "mgmt_cidrs" {
  description = "CIDR blocks allowed to reach the management/identity APIs (controlplane :19193, identityhub :7092). Defaults to none — operator must add their /32."
  type        = list(string)
  default     = []
}

variable "image_tag" {
  description = "Container image tag for the EDC services pulled from GHCR."
  type        = string
  default     = "latest"
}

variable "ghcr_credentials_secret_arn" {
  description = "Secrets Manager ARN for GHCR pull credentials ({\"username\":..., \"password\":...}). Create with scripts/upload-issuer-key.sh-style flow or per README prerequisites."
  type        = string
}

variable "issuer_private_key_secret_arn" {
  description = "Secrets Manager ARN holding the issuer PEM private key (raw PEM body). Read by the seeder ECS task to render did.json into EFS."
  type        = string
}

variable "dataplane_private_key_secret_arn" {
  description = "Secrets Manager ARN for the dataplane EDR-signing private key (PEM)."
  type        = string
}

variable "dataplane_public_key_secret_arn" {
  description = "Secrets Manager ARN for the dataplane EDR-signing public key (PEM)."
  type        = string
}

variable "ecs_cpu" {
  description = "Default CPU units per EDC service task."
  type        = number
  default     = 256
}

variable "ecs_memory" {
  description = "Default memory (MiB) per EDC service task."
  type        = number
  default     = 512
}

variable "db_username" {
  description = "RDS master username."
  type        = string
  default     = "edc"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}
