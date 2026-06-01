output "dashboard_name" {
  value = aws_cloudwatch_dashboard.this.dashboard_name
}

output "dashboard_url" {
  description = "Direct link to the CloudWatch dashboard in the AWS console."
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.this.dashboard_name}"
}
