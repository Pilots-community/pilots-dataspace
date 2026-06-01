################################################################################
# CloudWatch dashboard for the connector. Uses only the free AWS-native metrics
# (ECS, ApplicationELB, RDS) — no custom metric filters, no scheduled Logs
# Insights queries — so this stays at $0/month (account's first 3 dashboards
# are free; we have one).
#
# The widgets answer "did everything come up?" at a glance:
#   - ECS tasks running per service (target = desired = 1 for each)
#   - ALB target group health per route (target = 1 healthy host per TG)
#   - ALB 5xx error rate + request volume
#   - RDS CPU + connections (cheap sanity check on the DB)
################################################################################

locals {
  # Service-name → cluster name pair, replicated for each line on the ECS chart.
  # CloudWatch's GetMetricData syntax requires per-metric dimension pairs.
  ecs_service_metrics = [
    for svc in var.service_names :
    ["AWS/ECS", "RunningTaskCount", "ServiceName", svc, "ClusterName", var.cluster_name]
  ]

  tg_health_metrics = [
    for name, suffix in var.target_group_arn_suffixes :
    ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", suffix, "LoadBalancer", var.alb_arn_suffix, { label = name }]
  ]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name_prefix}-connector"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "text"
        x    = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "# ${var.name_prefix} connector\n\nIf any 'tasks running' line drops to 0, that service is down. If any TG 'healthy host' line drops to 0, the ALB can't reach that service even if the task is up — likely a healthcheck path / port mismatch. ALB 5xx near zero is good."
        }
      },
      {
        type = "metric"
        x    = 0, y = 2, width = 12, height = 6
        properties = {
          title   = "ECS tasks running per service (target: 1 each)"
          region  = var.region
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Average"
          metrics = local.ecs_service_metrics
          yAxis   = { left = { min = 0, max = 2 } }
        }
      },
      {
        type = "metric"
        x    = 12, y = 2, width = 12, height = 6
        properties = {
          title   = "ALB target health per route (target: 1 healthy)"
          region  = var.region
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Average"
          metrics = local.tg_health_metrics
          yAxis   = { left = { min = 0, max = 2 } }
        }
      },
      {
        type = "metric"
        x    = 0, y = 8, width = 12, height = 6
        properties = {
          title  = "ALB requests + 5xx (last hour)"
          region = var.region
          view   = "timeSeries"
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { label = "requests" }],
            [".", "HTTPCode_Target_5XX_Count", ".", ".", { label = "5xx from backend", color = "#d62728" }],
            [".", "HTTPCode_ELB_5XX_Count", ".", ".", { label = "5xx from ALB", color = "#ff7f0e" }],
          ]
        }
      },
      {
        type = "metric"
        x    = 12, y = 8, width = 12, height = 6
        properties = {
          title  = "ALB target response time"
          region = var.region
          view   = "timeSeries"
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix],
          ]
        }
      },
      {
        type = "metric"
        x    = 0, y = 14, width = 12, height = 6
        properties = {
          title  = "RDS CPU + connections"
          region = var.region
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_instance_identifier, { stat = "Average", yAxis = "left" }],
            [".", "DatabaseConnections", ".", ".", { stat = "Average", yAxis = "right" }],
          ]
        }
      },
    ]
  })
}
