locals {
  name_prefix = "pilots-${var.environment}"

  common_tags = {
    Project     = "pilots-dataspace"
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # All traffic enters on port 443 (path-based routing); no port encoding needed.
  # did:web:<domain>         → https://<domain>/.well-known/did.json  (identityhub)
  # did:web:<domain>:issuer  → https://<domain>/issuer/did.json       (nginx did-server)
  participant_did = "did:web:${var.root_domain}"
  issuer_did      = "did:web:${var.root_domain}:issuer"
}
