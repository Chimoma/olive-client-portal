resource "aws_ecs_cluster" "olive_cluster" {
  name = "olive-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "olive-cluster" }
}

resource "aws_cloudwatch_log_group" "olive_ecs_log_group" {
  name              = "/ecs/olive-task-def"
  retention_in_days = 30
}

resource "aws_ecs_task_definition" "olive_task_def" {
  family                   = "olive-task-def"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.olive_ecs_task_role.arn
  task_role_arn            = aws_iam_role.olive_ecs_task_role.arn

  # The pipeline (olive-pipeline) builds and pushes the application image to
  # olive-ecr-repo; CodeDeploy then updates this task definition's image tag
  # on each deployment.
  container_definitions = jsonencode([{
    name  = "olive-app-container"
    image = "${aws_ecr_repository.olive_ecr_repo.repository_url}:latest"
    portMappings = [{
      containerPort = var.container_port
      hostPort      = var.container_port
      protocol      = "tcp"
    }]
    secrets = [
      {
        name      = "DB_CREDENTIALS"
        valueFrom = aws_secretsmanager_secret.olive_db_secret.arn
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.olive_ecs_log_group.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "olive"
      }
    }
  }])

  tags = { Name = "olive-task-def" }
}

resource "aws_ecs_service" "olive_ecs_service" {
  name            = "olive-ecs-service"
  cluster         = aws_ecs_cluster.olive_cluster.id
  task_definition = aws_ecs_task_definition.olive_task_def.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.olive_private_subnet[*].id
    security_groups  = [aws_security_group.olive_ecs_sg.id]
    assign_public_ip = false
  }

  # Required so CodeDeploy can manage blue/green deployments for this
  # service instead of the standard ECS rolling-update controller.
  deployment_controller {
    type = "CODE_DEPLOY"
  }

  # Initial (blue) target group - CodeDeploy shifts traffic to green on
  # each deployment and swaps this back on the next one.
  load_balancer {
    target_group_arn = aws_lb_target_group.olive_tg_blue.arn
    container_name    = "olive-app-container"
    container_port    = var.container_port
  }

  # CodeDeploy takes over traffic shifting after the first deploy, so
  # Terraform should stop trying to manage the task definition/desired count
  # once the pipeline is live.
  lifecycle {
    ignore_changes = [task_definition, desired_count, load_balancer]
  }

  tags = { Name = "olive-ecs-service" }
}
