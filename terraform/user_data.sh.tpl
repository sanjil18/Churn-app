#!/bin/bash
set -e

# Install Docker
apt-get update -y
apt-get install -y docker.io awscli
systemctl enable docker
systemctl start docker

# Authenticate to ECR and pull the image
aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin ${ecr_repo_url}

# Pull and run the churn app container (assumes you've pushed a "latest" tag)
docker pull ${ecr_repo_url}:latest
docker run -d --restart unless-stopped -p ${app_port}:${app_port} --name churn-app ${ecr_repo_url}:latest
