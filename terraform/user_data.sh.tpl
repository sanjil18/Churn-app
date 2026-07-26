#!/bin/bash
set -e
set -x

# Install Docker (docker.io is fine via apt on Ubuntu 24.04)
apt-get update -y
apt-get install -y docker.io
systemctl enable docker
systemctl start docker

# Install AWS CLI v2 via the official installer.
# NOTE: the 'awscli' apt package was removed from Ubuntu 24.04's default repos,
# so it must be installed this way instead of via apt.
cd /tmp
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
apt-get install -y unzip
unzip -o awscliv2.zip
./aws/install

# Wait for the EC2 instance's IAM role credentials to become available via the
# instance metadata service before attempting ECR login. On first boot, this
# script can run before the role's temporary credentials have fully propagated,
# causing "Unable to locate credentials" if we don't wait for them.
echo "Waiting for IAM instance role credentials to become available..."
set +e
credentials_ready=0
for i in $(seq 1 12); do
  aws sts get-caller-identity --region ${aws_region} > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "IAM credentials are available (attempt $i)."
    credentials_ready=1
    break
  fi
  echo "Attempt $i: credentials not ready yet, waiting 5 seconds..."
  sleep 5
done
set -e

if [ "$credentials_ready" -ne 1 ]; then
  echo "ERROR: IAM instance role credentials never became available after 60 seconds. Aborting."
  exit 1
fi

# Authenticate to ECR and pull the image
aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin ${ecr_repo_url}

# Pull and run the churn app container (assumes you've pushed a "latest" tag)
docker pull ${ecr_repo_url}:latest
docker run -d --restart unless-stopped -p ${app_port}:${app_port} --name churn-app ${ecr_repo_url}:latest