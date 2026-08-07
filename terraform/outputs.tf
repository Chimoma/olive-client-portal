output "olive_alb_dns_name" {
  description = "Public URL of the Olive application (via the load balancer)"
  value       = aws_lb.olive_alb.dns_name
}

output "olive_db_endpoint" {
  description = "RDS SQL Server connection endpoint"
  value       = aws_db_instance.olive_db_instance.endpoint
  sensitive   = true
}

output "olive_db_secret_arn" {
  description = "Secrets Manager ARN holding DB credentials"
  value       = aws_secretsmanager_secret.olive_db_secret.arn
}

output "olive_redshift_endpoint" {
  description = "Redshift cluster endpoint"
  value       = aws_redshift_cluster.olive_redshift_cluster.endpoint
  sensitive   = true
}

output "olive_ecr_repo_url" {
  description = "ECR repository URL to push/pull the app image"
  value       = aws_ecr_repository.olive_ecr_repo.repository_url
}

output "olive_github_connection_arn" {
  description = "ARN of the GitHub connection - must be authorized manually in the AWS Console before the pipeline can run (see README.md Step 8)"
  value       = aws_codestarconnections_connection.olive_github_connection.arn
}

output "olive_github_connection_status" {
  description = "PENDING until manually authorized in the console; AVAILABLE once done"
  value       = aws_codestarconnections_connection.olive_github_connection.connection_status
}

output "olive_pipeline_name" {
  description = "Name of the CodePipeline"
  value       = aws_codepipeline.olive_pipeline.name
}

output "olive_cw_dashboard_url" {
  description = "Direct link to the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=olive-cw-dashboard"
}
