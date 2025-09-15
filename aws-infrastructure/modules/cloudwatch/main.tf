variable "project" { type = string }
variable "alb_arn_suffix" { type = string }
variable "alert_email" { type = string }
variable "asg_names" { type = string }
variable "log_retention_days" {
  type    = number
  default = 14
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ALB 5XX > 5 over 5m
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 5
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  statistic           = "Sum"
  period              = 300
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  alarm_name          = "${var.project}-alb-target-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 5
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  statistic           = "Sum"
  period              = 300
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}


# EC2/ASG avg CPU > 70% over 5m
resource "aws_cloudwatch_metric_alarm" "asg_cpu" {
  alarm_name          = "${var.project}-asg-cpu-${var.asg_names}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 70
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  statistic           = "Average"
  period              = 300
  dimensions          = { AutoScalingGroupName = var.asg_names }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

locals {
  log_groups = [
    "/${var.project}/nginx/access",
    "/${var.project}/nginx/error",
    "/${var.project}/gunicorn",
  ]
}

resource "aws_cloudwatch_log_group" "app" {
  for_each          = toset(local.log_groups)
  name              = each.value
  retention_in_days = var.log_retention_days
}