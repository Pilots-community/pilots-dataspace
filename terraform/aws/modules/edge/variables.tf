variable "name_prefix" {
  description = "Prefix for ALB and TG names. ALB names are length-restricted (<32)."
  type        = string
}

variable "root_domain" {
  description = "Root domain. Used for ACM cert SAN (root + wildcard) and Route53 zone."
  type        = string
}

variable "vpc_id" {
  description = "VPC id for target groups."
  type        = string
}

variable "public_subnet_ids" {
  description = "Subnets the ALB is attached to."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "ALB security group id (controls who can reach which listener port)."
  type        = string
}

# Each route becomes (a) an ALB target group on `target_port`, and
# (b) an HTTPS listener on `listener_port` whose default action forwards to
# that target group. Inter-listener routing is by port only — no path-based
# rules — so DSP / credentials / DID URLs match what other connectors expect.
variable "routes" {
  description = "One entry per backend service. Routes with path_patterns become ALB listener rules; the one with null path_patterns is the listener default action."
  type = list(object({
    name           = string
    target_port    = number
    path_patterns  = optional(list(string))
    priority       = optional(number)
    health_path    = string
    health_matcher = string
  }))
}
