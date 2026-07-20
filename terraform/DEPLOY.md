# Deploying to AWS (Week 3)

This provisions:
- **ECR** — private Docker registry to hold your image
- **EC2 (t3.micro)** — runs the container, free-tier eligible
- **Security group** — opens port 8000 (app) and 22 (SSH, restrict this)
- **Elastic IP** — fixed public IP so the URL doesn't change on restart
- **IAM role** — lets the EC2 instance pull from ECR without embedding credentials

## 1. Initialize Terraform

```bash
cd terraform
terraform init
```

## 2. Review the plan

```bash
terraform plan
```

Check the resources it intends to create. Nothing is provisioned yet at this step.

## 3. Apply

```bash
terraform apply
```

Type `yes` when prompted. This takes 1-2 minutes. At the end, Terraform prints outputs:
- `ecr_repository_url` — where you'll push your Docker image
- `app_public_url` — the live URL for your app (won't respond yet — no image pushed)
- `instance_public_ip`

## 4. Build and push your image to ECR

Replace `<ecr_repository_url>` with the value from the Terraform output.

```bash
# Authenticate Docker to your new ECR repo
aws ecr get-login-password --region eu-north-1 | docker login --username AWS --password-stdin <ecr_repository_url>

# Build the image (from the churn-app root, not the terraform folder)
cd ..
docker build -t churn-app .

# Tag it for ECR
docker tag churn-app:latest <ecr_repository_url>:latest

# Push
docker push <ecr_repository_url>:latest
```

## 5. Restart the EC2 instance (first time only)

The instance's `user_data` script runs once, on first boot, and tries to pull the image
immediately — but your image won't exist in ECR yet at that point (chicken-and-egg).
So after step 4, reboot the instance once to re-trigger the pull:

```bash
aws ec2 reboot-instances --instance-ids <instance-id>
```

Get the instance ID either from the AWS Console (EC2 → Instances) or:
```bash
aws ec2 describe-instances --filters "Name=tag:Project,Values=churn-app" \
  --query "Reservations[].Instances[].InstanceId" --output text
```

Give it ~1-2 minutes after reboot, then visit `app_public_url` from the Terraform output.

## 6. Updating the app later

Whenever you change your code or model:
```bash
docker build -t churn-app .
docker tag churn-app:latest <ecr_repository_url>:latest
docker push <ecr_repository_url>:latest
```
Then SSH into the instance and pull manually (fastest path, no reboot needed):
```bash
ssh ubuntu@<instance_public_ip>
sudo docker pull <ecr_repository_url>:latest
sudo docker stop churn-app && sudo docker rm churn-app
sudo docker run -d --restart unless-stopped -p 8000:8000 --name churn-app <ecr_repository_url>:latest
```

## 7. Tearing it down (avoid ongoing charges)

When you're done demoing/testing, or between sessions:
```bash
terraform destroy
```
This removes the EC2 instance, Elastic IP, security group, and IAM role. Your ECR
repository and images stay unless you delete them separately — they cost very little
to keep (a few cents/month for a small image).

## Cost notes

- `t3.micro` — free tier covers 750 hrs/month for 12 months on a new account; after
  that, roughly $0.01-0.02/hour depending on region
- Elastic IP — free while attached to a running instance; AWS charges a small hourly
  fee if it's allocated but *not* attached to anything, so don't leave it orphaned
  after a `terraform destroy` — the destroy removes it too, so this only matters if
  you ever manually detach it
- ECR storage — first 500MB/month free, then ~$0.10/GB/month
