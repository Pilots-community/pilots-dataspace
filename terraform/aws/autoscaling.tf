resource "aws_appautoscaling_target" "ecs_services" {
  for_each = local.autoscaled_routes

  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.pilots.name}/${aws_ecs_service.services[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 0
  max_capacity       = 1
}

resource "aws_appautoscaling_policy" "ecs_request_target_tracking" {
  for_each = local.autoscaled_routes

  name               = "pilots-${each.key}-requests"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_services[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_services[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_services[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 1
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.pilots_alb.arn_suffix}/${aws_lb_target_group.services[each.value].arn_suffix}"
    }
  }
}
