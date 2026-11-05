resource "aws_security_group" "churn_app_sg" {
  name        = "${var.project_name}-sg"
  description = "Allow HTTP/HTTPS app traffic and SSH"

  #tfsec:ignore:aws-ec2-no-public-ingress-sgr HTTP must be publicly reachable for web traffic.
  ingress {
    description = "HTTP - ACME challenge and redirect"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #tfsec:ignore:aws-ec2-no-public-ingress-sgr HTTPS must be publicly reachable for web traffic.
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  #tfsec:ignore:aws-ec2-no-public-egress-sgr Outbound internet access is required for package/image pulls.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project_name
  }
}
