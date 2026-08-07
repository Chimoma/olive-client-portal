# ---------------------------------------------------------------------------
# KMS - single key used to encrypt RDS, Redshift, ECR, Secrets Manager,
# and pipeline artifacts
# ---------------------------------------------------------------------------
resource "aws_kms_key" "olive_kms_key" {
  description             = "olive-kms-key - encryption for Olive data & CI/CD resources"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags = { Name = "olive-kms-key" }
}

resource "aws_kms_alias" "olive_kms_alias" {
  name          = "alias/olive-kms-key"
  target_key_id = aws_kms_key.olive_kms_key.key_id
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------

# ECS tasks: only accept traffic from the pipeline/ALB on the app port
resource "aws_security_group" "olive_ecs_sg" {
  name        = "olive-ecs-sg"
  description = "Allow inbound app traffic to Olive ECS tasks"
  vpc_id      = aws_vpc.olive_vpc.id

  ingress {
    description = "App port from within VPC"
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "olive-ecs-sg" }
}

# RDS: only accept SQL Server traffic (1433) from ECS tasks
resource "aws_security_group" "olive_rds_sg" {
  name        = "olive-rds-sg"
  description = "Allow SQL Server traffic from Olive ECS tasks only"
  vpc_id      = aws_vpc.olive_vpc.id

  ingress {
    description     = "SQL Server from ECS tasks"
    from_port       = 1433
    to_port         = 1433
    protocol        = "tcp"
    security_groups = [aws_security_group.olive_ecs_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "olive-rds-sg" }
}

# Redshift: accept traffic on 5439 from within the VPC (BI tools, ECS ETL jobs)
resource "aws_security_group" "olive_redshift_sg" {
  name        = "olive-redshift-sg"
  description = "Allow Redshift traffic from within the Olive VPC"
  vpc_id      = aws_vpc.olive_vpc.id

  ingress {
    description = "Redshift from within VPC"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "olive-redshift-sg" }
}

# ---------------------------------------------------------------------------
# IAM - ECS Task Execution Role (lets ECS pull images / write logs)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "olive_ecs_task_role" {
  name = "olive-ecs-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "olive_ecs_task_execution" {
  role       = aws_iam_role.olive_ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Lets the running app read its DB credentials from Secrets Manager
resource "aws_iam_role_policy" "olive_ecs_secrets_access" {
  name = "olive-ecs-secrets-access"
  role = aws_iam_role.olive_ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.olive_db_secret.arn]
    }]
  })
}

# ---------------------------------------------------------------------------
# IAM - CodeBuild Role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "olive_codebuild_role" {
  name = "olive-codebuild-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "olive_codebuild_policy" {
  name = "olive-codebuild-policy"
  role = aws_iam_role.olive_codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.olive_pipeline_artifacts.arn}/*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# IAM - CodePipeline Role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "olive_codepipeline_role" {
  name = "olive-codepipeline-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "olive_codepipeline_policy" {
  name = "olive-codepipeline-policy"
  role = aws_iam_role.olive_codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.olive_pipeline_artifacts.arn,
          "${aws_s3_bucket.olive_pipeline_artifacts.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["codebuild:BatchGetBuilds", "codebuild:StartBuild"]
        Resource = aws_codebuild_project.olive_build.arn
      },
      {
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:GetApplicationRevision",
          "codedeploy:RegisterApplicationRevision"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ecs:DescribeServices", "ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "*"
        Condition = {
          StringEqualsIfExists = {
            "iam:PassedToService" = ["ecs-tasks.amazonaws.com"]
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# IAM - CodeDeploy Role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "olive_codedeploy_role" {
  name = "olive-codedeploy-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "olive_codedeploy_ecs_policy" {
  role       = aws_iam_role.olive_codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}
