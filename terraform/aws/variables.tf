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
  description = "Container image tag for the EDC services. Set by scripts/build-and-push.sh output (short SHA) or 'latest' for dev iteration."
  type        = string
  default     = "latest"
}

variable "image_registry" {
  description = "Container image registry base URL (without trailing slash). Empty = derive '<account>.dkr.ecr.<region>.amazonaws.com/pilots' from the active account+region. Override to use a different registry (e.g. a private GHCR org)."
  type        = string
  default     = ""
}

variable "ghcr_credentials_secret_arn" {
  description = "OPTIONAL. Secrets Manager ARN for GHCR pull credentials ({\"username\":..., \"password\":...}). Only needed if image_registry points at a private GHCR org. ECR pulls do NOT need this — they use the execution role."
  type        = string
  default     = ""
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
