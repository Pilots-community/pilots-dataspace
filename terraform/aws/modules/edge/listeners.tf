locals {
  routes_by_name = { for r in var.routes : r.name => r }
}

resource "aws_lb_target_group" "this" {
  for_each = local.routes_by_name

  name        = substr("${var.name_prefix}-${each.value.name}", 0, 32)
  port        = each.value.target_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = each.value.health_path
    matcher             = each.value.health_matcher
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }

  deregistration_delay = 30
}

resource "aws_lb_listener" "this" {
  for_each = local.routes_by_name

  load_balancer_arn = aws_lb.this.arn
  port              = each.value.listener_port
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.wildcard.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }
}
