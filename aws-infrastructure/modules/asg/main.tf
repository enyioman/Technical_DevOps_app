# modules/asg/main.tf — EC2 ASG running Django via Gunicorn behind Nginx, fronted by ALB

# -------- Variables --------
variable "project" { type = string }
variable "aws_region" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "target_group_arn" { type = string }
variable "instance_type" { type = string }
variable "key_name" { type = string }
variable "iam_instance_profile" { type = string }

variable "app_repo_url" { type = string }  
variable "app_branch" { type = string }    
variable "allowed_hosts" { type = string } 
variable "static_bucket_name" { type = string }
variable "secrets_name" { type = string } 
variable "alb_sg_id" { type = string }

variable "min_size" { type = number }
variable "desired_capacity" { type = number }
variable "max_size" { type = number }

variable "django_secret_key" {
  type      = string
  sensitive = true
}

# -------- AMI --------
# data "aws_ami" "al2023" {
#   most_recent = true
#   owners      = ["137112412989"] # Amazon
#   filter {
#     name   = "name"
#     values = ["al2023-ami-*-x86_64"]
#   }
# }

data "aws_ami" "amzn2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-2.0.*-x86_64-gp2"]
  }
}

# -------- Security Group (ALB -> EC2:80) --------
resource "aws_security_group" "ec2" {
  name   = "${var.project}-ec2-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [var.alb_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-ec2-sg" }
}

# -------- User Data (single Nginx server; install awscli; consistent env names) --------
locals {
  init_health_user_data = base64encode(<<-BASH
    #!/bin/bash
    set -euxo pipefail

    # Install nginx (AL2023 uses dnf, AL2 uses yum)
    if command -v dnf >/dev/null 2>&1; then
      dnf install -y nginx
    else
      amazon-linux-extras install -y nginx1 || yum install -y nginx
    fi

    # Minimal nginx that serves 200 on /healthz immediately
    cat >/etc/nginx/nginx.conf <<'CONF'
    user nginx;
    worker_processes auto;
    error_log /var/log/nginx/error.log;
    pid /run/nginx.pid;
    events { worker_connections 1024; }
    http {
      include /etc/nginx/mime.types;
      default_type application/octet-stream;
      access_log /var/log/nginx/access.log combined;
      sendfile on;
      keepalive_timeout 65;
      include /etc/nginx/conf.d/*.conf;
    }
    CONF

    mkdir -p /etc/nginx/conf.d
    cat >/etc/nginx/conf.d/health.conf <<'CONF'
    server {
      listen 80 default_server;
      server_name _;
      location = /healthz { default_type text/plain; return 200 "ok\n"; }
      location / { return 200 "booting\n"; }
    }
    CONF

    nginx -t
    systemctl enable --now nginx
  BASH
  )
}

# -------- Launch Template --------
resource "aws_launch_template" "lt" {
  name_prefix   = "${var.project}-lt-"
  image_id      = data.aws_ami.amzn2.id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile { name = var.iam_instance_profile }
  user_data = local.init_health_user_data

  network_interfaces {
    security_groups             = [aws_security_group.ec2.id]
    associate_public_ip_address = false
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project}-app" }
  }
}

# -------- Auto Scaling Group --------
resource "aws_autoscaling_group" "asg" {
  name                      = "${var.project}-asg"
  min_size                  = var.min_size
  desired_capacity          = var.desired_capacity
  max_size                  = var.max_size
  vpc_zone_identifier       = var.private_subnet_ids
  target_group_arns         = [var.target_group_arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-app"
    propagate_at_launch = true
  }
}

# -------- Outputs --------
output "asg_name" { value = aws_autoscaling_group.asg.name }
output "ec2_sg_id" { value = aws_security_group.ec2.id }
