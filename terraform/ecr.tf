# ECR repository to store the Docker image for the churn app
resource "aws_ecr_repository" "churn_app" {
  name                 = "${var.project_name}-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = var.project_name
  }
}

# Keep only the last 5 images to avoid unbounded storage growth
resource "aws_ecr_lifecycle_policy" "churn_app_policy" {
  repository = aws_ecr_repository.churn_app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
