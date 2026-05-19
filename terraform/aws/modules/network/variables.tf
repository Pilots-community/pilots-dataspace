variable "name_prefix" {
  description = "Prefix applied to security-group names."
  type        = string
}

variable "mgmt_cidrs" {
  description = "CIDRs allowed to reach the operator-facing ports (443, 7092, 19193). Empty list = closed."
  type        = list(string)
}

# Ports that peer connectors must reach over HTTPS on the ALB. Each gets its
# own ALB listener (mapped 1:1 by port) so that did:web URIs that include the
# port (e.g. did:web:domain%3A7093) resolve straight to the right target group.
variable "peer_ports" {
  description = "TCP ports exposed to the public internet on the ALB (peer-connector traffic)."
  type        = list(number)
  default     = [7091, 7093, 9876, 19194, 38185]
}

# Ports that operate management APIs. Same listener model, but SG-restricted.
variable "mgmt_ports" {
  description = "TCP ports exposed only to mgmt_cidrs on the ALB."
  type        = list(number)
  default     = [7092, 19193]
}
