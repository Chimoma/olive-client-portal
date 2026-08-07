resource "aws_cloudwatch_dashboard" "olive_cw_dashboard" {
  dashboard_name = "olive-cw-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x = 0, y = 0, width = 12, height = 6
        properties = {
          title   = "Olive ECS - CPU & Memory Utilization"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", "olive-cluster", "ServiceName", "olive-ecs-service"],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", "olive-cluster", "ServiceName", "olive-ecs-service"]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x = 12, y = 0, width = 12, height = 6
        properties = {
          title   = "Olive RDS - CPU & Free Storage"
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "olive-db-instance"],
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", "olive-db-instance"]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x = 0, y = 6, width = 12, height = 6
        properties = {
          title   = "Olive Redshift - CPU Utilization"
          metrics = [
            ["AWS/Redshift", "CPUUtilization", "ClusterIdentifier", "olive-redshift-cluster"]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
        }
      }
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "olive_db_cpu_alarm" {
  alarm_name          = "olive-db-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Triggers when olive-db-instance CPU exceeds 80% for 10 minutes"
  dimensions = { DBInstanceIdentifier = aws_db_instance.olive_db_instance.id }
  tags = { Name = "olive-db-high-cpu" }
}

resource "aws_cloudwatch_metric_alarm" "olive_ecs_cpu_alarm" {
  alarm_name          = "olive-ecs-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Triggers when olive-ecs-service CPU exceeds 80% for 10 minutes"
  dimensions = {
    ClusterName = aws_ecs_cluster.olive_cluster.name
    ServiceName = aws_ecs_service.olive_ecs_service.name
  }
  tags = { Name = "olive-ecs-high-cpu" }
}

resource "aws_cloudwatch_metric_alarm" "olive_db_low_storage_alarm" {
  alarm_name          = "olive-db-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 10737418240 # 10 GB in bytes
  alarm_description   = "Triggers when olive-db-instance free storage drops below 10 GB"
  dimensions = { DBInstanceIdentifier = aws_db_instance.olive_db_instance.id }
  tags = { Name = "olive-db-low-storage" }
}
