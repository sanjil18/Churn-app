# Look up the latest Ubuntu 24.04 AMI for the region, instead of hardcoding an AMI ID
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "churn_app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.churn_app_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ecr_profile.name

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    aws_region  = var.aws_region
    ecr_repo_url = aws_ecr_repository.churn_app.repository_url
    app_port    = var.app_port
  })

  tags = {
    Name    = var.project_name
    Project = var.project_name
  }
}

# Elastic IP so the public address stays fixed even if the instance restarts
resource "aws_eip" "churn_app_eip" {
  instance = aws_instance.churn_app.id
  domain   = "vpc"

  tags = {
    Project = var.project_name
  }
}
