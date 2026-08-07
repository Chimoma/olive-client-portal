# ---------------------------------------------------------------------------
# S3 bucket for pipeline artifacts
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "olive_pipeline_artifacts" {
  bucket = "olive-pipeline-artifacts-${data.aws_caller_identity.current.account_id}"
  tags   = { Name = "olive-pipeline-artifacts" }
}

resource "aws_s3_bucket_versioning" "olive_pipeline_artifacts_versioning" {
  bucket = aws_s3_bucket.olive_pipeline_artifacts.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "olive_pipeline_artifacts_sse" {
  bucket = aws_s3_bucket.olive_pipeline_artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.olive_kms_key.arn
      sse_algorithm      = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "olive_pipeline_artifacts_block" {
  bucket                  = aws_s3_bucket.olive_pipeline_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# GitHub connection - AWS needs an authorized connection to your GitHub
# account before CodePipeline can read from a repo there. Terraform can
# create this connection object, but it starts in "PENDING" state - you
# must manually authorize it once in the AWS Console (see README.md Step 8).
# ---------------------------------------------------------------------------
resource "aws_codestarconnections_connection" "olive_github_connection" {
  name          = "olive-github-connection"
  provider_type = "GitHub"
  tags          = { Name = "olive-github-connection" }
}

# ---------------------------------------------------------------------------
# CodeBuild
# ---------------------------------------------------------------------------
resource "aws_codebuild_project" "olive_build" {
  name         = "olive-build"
  service_role = aws_iam_role.olive_codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true # required to build/push Docker images

    environment_variable {
      name  = "ECR_REPO_URL"
      value = aws_ecr_repository.olive_ecr_repo.repository_url
    }
    environment_variable {
      name  = "AWS_REGION"
      value = var.aws_region
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml" # lives in olive-app-repo, see olive-app/
  }

  tags = { Name = "olive-build" }
}

# ---------------------------------------------------------------------------
# CodeDeploy (ECS blue/green)
# ---------------------------------------------------------------------------
resource "aws_codedeploy_app" "olive_deploy_app" {
  name             = "olive-deploy-app"
  compute_platform = "ECS"
}

resource "aws_codedeploy_deployment_group" "olive_deploy_group" {
  app_name               = aws_codedeploy_app.olive_deploy_app.name
  deployment_group_name  = "olive-deploy-group"
  service_role_arn       = aws_iam_role.olive_codedeploy_role.arn
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"

  ecs_service {
    cluster_name = aws_ecs_cluster.olive_cluster.name
    service_name = aws_ecs_service.olive_ecs_service.name
  }

  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  blue_green_deployment_config {
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.olive_alb_listener.arn]
      }
      target_group {
        name = aws_lb_target_group.olive_tg_blue.name
      }
      target_group {
        name = aws_lb_target_group.olive_tg_green.name
      }
    }
  }

  tags = { Name = "olive-deploy-group" }
}

# ---------------------------------------------------------------------------
# Application Load Balancer (required for ECS blue/green deployments)
# ---------------------------------------------------------------------------
resource "aws_security_group" "olive_alb_sg" {
  name        = "olive-alb-sg"
  description = "Allow inbound HTTP to the Olive ALB"
  vpc_id      = aws_vpc.olive_vpc.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "olive-alb-sg" }
}

resource "aws_lb" "olive_alb" {
  name               = "olive-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.olive_alb_sg.id]
  subnets            = aws_subnet.olive_public_subnet[*].id
  tags               = { Name = "olive-alb" }
}

resource "aws_lb_target_group" "olive_tg_blue" {
  name        = "olive-tg-blue"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.olive_vpc.id
  target_type = "ip"
  health_check {
    path = "/"
  }
  tags = { Name = "olive-tg-blue" }
}

resource "aws_lb_target_group" "olive_tg_green" {
  name        = "olive-tg-green"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.olive_vpc.id
  target_type = "ip"
  health_check {
    path = "/"
  }
  tags = { Name = "olive-tg-green" }
}

resource "aws_lb_listener" "olive_alb_listener" {
  load_balancer_arn = aws_lb.olive_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.olive_tg_blue.arn
  }
}

# ---------------------------------------------------------------------------
# CodePipeline - orchestrates Source -> Build -> Deploy
# ---------------------------------------------------------------------------
resource "aws_codepipeline" "olive_pipeline" {
  name     = "olive-pipeline"
  role_arn = aws_iam_role.olive_codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.olive_pipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.olive_github_connection.arn
        FullRepositoryId = var.github_repo
        BranchName       = var.github_branch
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      configuration = {
        ProjectName = aws_codebuild_project.olive_build.name
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      version         = "1"
      input_artifacts = ["build_output"]
      configuration = {
        ApplicationName                = aws_codedeploy_app.olive_deploy_app.name
        DeploymentGroupName            = aws_codedeploy_deployment_group.olive_deploy_group.deployment_group_name
        TaskDefinitionTemplateArtifact = "build_output"
        AppSpecTemplateArtifact        = "build_output"
      }
    }
  }

  tags = { Name = "olive-pipeline" }
}
