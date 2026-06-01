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

# HTTP (80) — public, used only for the 80→443 redirect listener.
resource "aws_vpc_security_group_ingress_rule" "alb_http_public" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "HTTP redirect to HTTPS"
}

# HTTPS (443) — public. All traffic (peer + operator) enters here; path-based
# routing on the ALB forwards to the right backend. Mgmt path restriction
# is a follow-up (WAF/listener-rule source-IP condition).
resource "aws_vpc_security_group_ingress_rule" "alb_https_public" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS (all paths, single entry point)"
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

# Inter-service traffic over CloudMap DNS. Self-ingress on all TCP covers
# every container port without enumerating each one.
resource "aws_vpc_security_group_ingress_rule" "ecs_self" {
  security_group_id            = aws_security_group.ecs_tasks.id
  referenced_security_group_id = aws_security_group.ecs_tasks.id
  ip_protocol                  = "tcp"
  from_port                    = 0
  to_port                      = 65535
  description                  = "Inter-service traffic (CloudMap)"
}

# ALB -> ECS on each backend container port (the ALB still connects on the
# service's own port even though the external listener is 443 only).
locals {
  alb_to_ecs_ports = [80, 7091, 7092, 7093, 9876, 19193, 19194, 38185]
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  for_each = toset([for p in local.alb_to_ecs_ports : tostring(p)])

  security_group_id            = aws_security_group.ecs_tasks.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
  description                  = "ALB to ECS port ${each.value}"
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
