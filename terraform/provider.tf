terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Name prefix used for all resources"
  type        = string
  default     = "churn-app"
}

variable "instance_type" {
  description = "EC2 instance type (t3.micro is free-tier eligible in most regions)"
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "Port the FastAPI app listens on inside the container"
  type        = number
  default     = 8000
}

variable "ssh_cidr" {
  description = "CIDR allowed to SSH into the instance. Set to your own IP/32 for security, not 0.0.0.0/0."
  type        = string
  default     = "127.0.0.1/32"
}

variable "alert_email" {
  description = "Email address that receives CloudWatch alarm notifications"
  type        = string
  default     = "sanjilraj2@gmail.com"
}
