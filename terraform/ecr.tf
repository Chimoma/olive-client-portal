resource "aws_ecr_repository" "olive_ecr_repo" {
  name                 = "olive-ecr-repo"
  image_tag_mutability = "IMMUTABLE"

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.olive_kms_key.arn
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "olive-ecr-repo" }
}

resource "aws_ecr_lifecycle_policy" "olive_ecr_lifecycle" {
  repository = aws_ecr_repository.olive_ecr_repo.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
