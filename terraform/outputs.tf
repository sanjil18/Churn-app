output "ecr_repository_url" {
  description = "Push your Docker image here before/after the first apply"
  value       = aws_ecr_repository.churn_app.repository_url
}

output "app_public_url" {
  description = "Public URL for the deployed churn app (may take ~1-2 min after apply to respond)"
  value       = "http://${aws_eip.churn_app_eip.public_ip}:${var.app_port}"
}

output "instance_public_ip" {
  value = aws_eip.churn_app_eip.public_ip
}
