variable "project" {}
variable "vpc_id" {}
variable "private_subnet_ids" { type = list(string) }
variable "db_name" {}
variable "db_user" {}
variable "db_password" {}
variable "db_port" { default = 5432 }
variable "instance_class" {}
variable "storage" {}
variable "multi_az" { default = true }

resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-dbsubnet"
  subnet_ids = var.private_subnet_ids
  tags       = { Name = "${var.project}-dbsubnet" }
}

resource "aws_security_group" "rds" {
  name   = "${var.project}-rds-sg"
  vpc_id = var.vpc_id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project}-rds-sg" }
}

resource "aws_db_instance" "this" {
  identifier             = "${var.project}-pg"
  engine                 = "postgres"
  instance_class         = var.instance_class
  allocated_storage      = var.storage
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_name                = var.db_name
  username               = var.db_user
  password               = var.db_password
  port                   = var.db_port
  multi_az               = var.multi_az
  publicly_accessible    = false
  skip_final_snapshot    = true
  apply_immediately      = true

  tags = { Name = "${var.project}-pg" }
}

output "db_endpoint" { value = aws_db_instance.this.address }
output "rds_sg_id" { value = aws_security_group.rds.id }
