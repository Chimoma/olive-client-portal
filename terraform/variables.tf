variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (staging, prod)"
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "CIDR block for the Olive VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_username" {
  description = "Master username for RDS SQL Server (also used for Redshift)"
  type        = string
  default     = "olive_admin"
}

variable "db_instance_class" {
  description = "Instance class for the RDS SQL Server database"
  type        = string
  default     = "db.m5.large"
}

variable "redshift_node_type" {
  description = "Node type for the Redshift analytics cluster"
  type        = string
  default     = "ra3.xlplus"
}

variable "container_port" {
  description = "Port the .NET app listens on inside the container"
  type        = number
  default     = 8080
}

variable "ecs_desired_count" {
  description = "Number of ECS tasks to run"
  type        = number
  default     = 2
}

variable "github_repo" {
  description = "GitHub repository in 'owner/repo-name' format that CodePipeline builds from"
  type        = string
}

variable "github_branch" {
  description = "Branch CodePipeline watches for changes"
  type        = string
  default     = "main"
}
