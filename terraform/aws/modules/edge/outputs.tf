output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  value = aws_lb.this.zone_id
}

output "zone_id" {
  value = aws_route53_zone.this.zone_id
}

output "nameservers" {
  value = aws_route53_zone.this.name_servers
}

output "certificate_arn" {
  value = aws_acm_certificate_validation.wildcard.certificate_arn
}

output "target_group_arns" {
  description = "Map of route name -> target group ARN. Consumed by ECS services to attach as load-balancer targets."
  value       = { for k, tg in aws_lb_target_group.this : k => tg.arn }
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (app/<name>/<id>), used as the CloudWatch LoadBalancer dimension."
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn_suffixes" {
  description = "Map of route name -> TG ARN suffix, used as the CloudWatch TargetGroup dimension."
  value       = { for k, tg in aws_lb_target_group.this : k => tg.arn_suffix }
}
