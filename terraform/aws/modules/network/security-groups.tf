resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb"
  description = "ALB ingress for the pilots connector."
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Public HTTP redirect (80 -> 443). Always world-open; redirect target is
# behind the same SG and may be blocked, but that's fine.
resource "aws_vpc_security_group_ingress_rule" "alb_http_public" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "HTTP redirect to HTTPS"
}

# 443 (dashboard) is operator-only. Same with each mgmt port. Closed by
# default; operator must populate mgmt_cidrs.
resource "aws_vpc_security_group_ingress_rule" "alb_mgmt_443" {
  for_each = toset(var.mgmt_cidrs)

  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "Dashboard / apex HTTPS (operator-only)"
}

resource "aws_vpc_security_group_ingress_rule" "alb_mgmt_high" {
  for_each = {
    for pair in setproduct(var.mgmt_ports, var.mgmt_cidrs) :
    "${pair[0]}-${pair[1]}" => { port = pair[0], cidr = pair[1] }
  }

  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = each.value.cidr
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  description       = "Mgmt port ${each.value.port} from operator CIDR"
}

# Peer-facing ports are world-open: DSP, credentials, did, data fetch.
resource "aws_vpc_security_group_ingress_rule" "alb_peer" {
  for_each = toset([for p in var.peer_ports : tostring(p)])

  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  description       = "Peer port ${each.value} (public)"
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.name_prefix}-ecs-tasks"
  description = "ECS task ingress: ALB on app ports, self on all TCP for inter-service."
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Inter-service traffic over CloudMap DNS. All container ports are reached
# only by other tasks in the same SG, so a single self-ingress on all TCP is
# safe and avoids enumerating every port.
resource "aws_vpc_security_group_ingress_rule" "ecs_self" {
  security_group_id            = aws_security_group.ecs_tasks.id
  referenced_security_group_id = aws_security_group.ecs_tasks.id
  ip_protocol                  = "tcp"
  from_port                    = 0
  to_port                      = 65535
  description                  = "Inter-service traffic (CloudMap)"
}

# ALB -> ECS on each exposed app port (peer ports + mgmt ports + 80 for dashboard).
locals {
  alb_to_ecs_ports = concat([80], var.peer_ports, var.mgmt_ports)
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  for_each = toset([for p in local.alb_to_ecs_ports : tostring(p)])

  security_group_id            = aws_security_group.ecs_tasks.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
  description                  = "ALB -> ECS port ${each.value}"
}

resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds"
  description = "Postgres ingress from ECS tasks."
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_ecs" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.ecs_tasks.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "Postgres from ECS tasks"
}

resource "aws_security_group" "efs" {
  name        = "${var.name_prefix}-efs"
  description = "EFS NFS ingress from ECS tasks."
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_ecs" {
  security_group_id            = aws_security_group.efs.id
  referenced_security_group_id = aws_security_group.ecs_tasks.id
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
  description                  = "NFS from ECS tasks"
}
