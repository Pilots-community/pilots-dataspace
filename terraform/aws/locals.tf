locals {
  name_prefix = "pilots-${var.environment}"

  common_tags = {
    Project     = "pilots-dataspace"
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # DIDs are URL-encoded (port is %3A<port>). Peers resolve these to
  # https://${root_domain}:<port>/.well-known/did.json — that's why each
  # peer-facing port gets its own ALB listener on the wildcard cert.
  participant_did = "did:web:${var.root_domain}%3A7093"
  issuer_did      = "did:web:${var.root_domain}%3A9876"
}
