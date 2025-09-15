variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "project" {
  type    = string
  default = "cognetiks-tech"
}
variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}
variable "az_count" {
  type    = number
  default = 2
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}
variable "key_name" {
  type    = string
  default = "~/aws/aws_keys/sysuser1.pem"
}

# Django app settings
variable "app_repo_url" {
  type    = string
  default = "https://github.com/cognetiks/Technical_DevOps_app.git"
}
variable "app_branch" {
  type    = string
  default = "main"
}
variable "django_secret_key" {
  type = string
}
variable "allowed_hosts" {
  type    = string
  default = "*"
}

# DB params
variable "db_name" {
  type    = string
  default = "appdb"
}
variable "db_user" {
  type    = string
  default = "appuser"
}
variable "db_port" {
  type    = number
  default = 5432
}
variable "db_password" {
  type      = string
  sensitive = true
}
variable "db_allocated_storage" {
  type    = number
  default = 20
}
variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}
variable "multi_az" {
  type    = bool
  default = true
}

# S3 buckets
variable "static_bucket_name" {
  type = string
}
variable "logs_bucket_name" {
  type = string
}

# Alerts
variable "alert_email" {
  type = string
}


