resource "aws_appautoscaling_target" "ecs_services" {
  for_each = local.autoscaled_routes

  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.pilots.name}/${aws_ecs_service.services[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 0
  max_capacity       = 1
}

################################################################################
# Scale Up (Requests >= 1)
################################################################################

resource "aws_appautoscaling_policy" "scale_up" {
  for_each = local.autoscaled_routes

  name               = "pilots-${each.key}-scale-up"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.ecs_services[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_services[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_services[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ExactCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "request_count_high" {
  for_each = local.autoscaled_routes

  alarm_name          = "pilots-${each.key}-request-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "RequestCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Scale up when request count >= 1"

  dimensions = {
    LoadBalancer = aws_lb.pilots_alb.arn_suffix
    TargetGroup  = aws_lb_target_group.services[each.value].arn_suffix
  }

  treat_missing_data = "notBreaching"
  alarm_actions      = [aws_appautoscaling_policy.scale_up[each.key].arn]
}

################################################################################
# Scale Down (Requests == 0 for 15 mins)
################################################################################

resource "aws_appautoscaling_policy" "scale_down" {
  for_each = local.autoscaled_routes

  name               = "pilots-${each.key}-scale-down"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.ecs_services[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_services[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_services[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ExactCapacity"
    cooldown                = 300
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = 0
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "request_count_low" {
  for_each = local.autoscaled_routes

  alarm_name          = "pilots-${each.key}-request-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "RequestCount"
  namespace           = "AWS/ApplicationELB"
  period              = "900" # 15 minutes
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Scale down when request count == 0 for 15 mins"

  dimensions = {
    LoadBalancer = aws_lb.pilots_alb.arn_suffix
    TargetGroup  = aws_lb_target_group.services[each.value].arn_suffix
  }

  treat_missing_data = "breaching" # No data means no requests -> scale down
  alarm_actions      = [aws_appautoscaling_policy.scale_down[each.key].arn]
}
