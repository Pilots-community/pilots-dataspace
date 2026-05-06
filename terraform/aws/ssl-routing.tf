################################################################################
# Route 53 & Domain Setup
################################################################################

resource "aws_route53_zone" "pilots" {
  name = var.root_domain
  tags = {
    Environment = var.environment
  }
}

################################################################################
# SSL Certificate (ACM)
################################################################################

resource "aws_acm_certificate" "wildcard" {
  domain_name       = var.root_domain
  validation_method = "DNS"

  subject_alternative_names = [
    "*.${var.root_domain}",
    "*.${var.environment}.${var.root_domain}"
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.pilots.zone_id
}

resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

################################################################################
# Application Load Balancer
################################################################################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "alb_sg" {
  name        = "pilots-alb-sg"
  description = "Allow HTTPS and HTTP to ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # For redirecting to HTTPS
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "pilots_alb" {
  name               = "pilots-connector-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids

  tags = {
    Environment = var.environment
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.pilots_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate_validation.wildcard.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.pilots_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

################################################################################
# Routing Rules & Target Groups
################################################################################

locals {
  service_mappings = {
    dashboard  = { port = 80, path = "/dashboard*" }
    credentials = { port = 7091, path = "/credentials*" }
    did-api    = { port = 7093, path = "/did-api*" }
    did-server = { port = 9876, path = "/did-server*" }
    dsp        = { port = 19194, path = "/dsp*" }
    data       = { port = 38185, path = "/data*" }
  }
}

resource "aws_lb_target_group" "services" {
  for_each = local.service_mappings

  name     = "tg-${each.key}"
  port     = each.value.port
  protocol = "HTTP"
  target_type = "ip"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/" # Default health check, might need tuning per service
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-499" # Allow a range as some services might return 401/404 on /
  }
}

resource "aws_lb_listener_rule" "service_routing" {
  for_each = local.service_mappings

  listener_arn = aws_lb_listener.https.arn
  priority     = index(keys(local.service_mappings), each.key) + 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services[each.key].arn
  }

  condition {
    path_pattern {
      values = [each.value.path]
    }
  }
}

################################################################################
# Route 53 Aliases for Services
################################################################################

resource "aws_route53_record" "root" {
  zone_id = aws_route53_zone.pilots.zone_id
  name    = var.root_domain
  type    = "A"

  alias {
    name                   = aws_lb.pilots_alb.dns_name
    zone_id                = aws_lb.pilots_alb.zone_id
    evaluate_target_health = true
  }
}

################################################################################
# Outputs
################################################################################

output "route53_nameservers" {
  description = "The nameservers for the new Route53 zone. Add these NS records to your DNS provider for the root domain"
  value       = aws_route53_zone.pilots.name_servers
}

output "service_urls" {
  description = "The HTTPS URLs for the services"
  value       = { for k, v in local.service_mappings : k => "https://${var.root_domain}${replace(v.path, "*", "")}" }
}
