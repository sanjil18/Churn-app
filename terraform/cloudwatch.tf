# ---------------------------------------------------------------------------
# SNS topic for alerts
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------------------------------------------------------------------------
# CPU utilization alarm (built-in EC2 metric, no agent needed)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-high-cpu"
  alarm_description   = "Average CPU above 80 percent for 10 minutes"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  dimensions = {
    InstanceId = aws_instance.churn_app.id
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# ---------------------------------------------------------------------------
# EC2 status check failed alarm (built-in metric, no agent needed)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "status_check_failed" {
  alarm_name          = "${var.project_name}-status-check-failed"
  alarm_description   = "Instance failed an EC2 status check"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  dimensions = {
    InstanceId = aws_instance.churn_app.id
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# ---------------------------------------------------------------------------
# Nginx 5xx errors, via CloudWatch agent shipping the access log
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "nginx_access" {
  name              = "/${var.project_name}/nginx/access"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_metric_filter" "nginx_5xx" {
  name           = "${var.project_name}-nginx-5xx"
  log_group_name = aws_cloudwatch_log_group.nginx_access.name
  pattern        = "[ip, user, authuser, timestamp, request, status_code=5*, size, referrer, agent]"

  metric_transformation {
    name          = "Nginx5xxCount"
    namespace     = "ChurnApp"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "nginx_5xx" {
  alarm_name          = "${var.project_name}-nginx-5xx"
  alarm_description   = "One or more nginx 5xx responses in a 1-minute window"
  namespace           = "ChurnApp"
  metric_name         = "Nginx5xxCount"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# ---------------------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "churn_app" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "CPU Utilization"
          region  = var.aws_region
          metrics = [["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.churn_app.id]]
          period  = 300
          stat    = "Average"
          view    = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "EC2 Status Check Failed"
          region  = var.aws_region
          metrics = [["AWS/EC2", "StatusCheckFailed", "InstanceId", aws_instance.churn_app.id]]
          period  = 60
          stat    = "Maximum"
          view    = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Nginx 5xx Responses"
          region  = var.aws_region
          metrics = [["ChurnApp", "Nginx5xxCount"]]
          period  = 60
          stat    = "Sum"
          view    = "timeSeries"
        }
      }
    ]
  })
}
