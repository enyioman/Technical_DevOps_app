variable "db_name" {
  type    = string
  default = "appdb"
}
variable "db_username" {
  type    = string
  default = "appuser"
}
variable "db_engine_version" {
  type    = string
  default = "16"
}
variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}
variable "db_multi_az" {
  type    = bool
  default = false
}
variable "db_allocated_storage" {
  type    = number
  default = 20
}

# Password
resource "random_password" "db" {
  length  = 20
  special = true
}

# SG allowing traffic from EKS worker nodes
resource "aws_security_group" "rds" {
  name        = "${var.project}-rds-sg"
  description = "RDS inbound from EKS nodes"
  vpc_id      = module.vpc.vpc_id
  tags        = { Project = var.project }
}

# Inbound Postgres from node group security group
resource "aws_security_group_rule" "rds_in_pg_from_nodes" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = module.eks.node_security_group_id
}

# Egress anywhere (or restrict if you prefer)
resource "aws_security_group_rule" "rds_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.rds.id
  cidr_blocks       = ["0.0.0.0/0"]
}

# Simple RDS instance (use the module for speed)
module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "6.7.0"

  identifier = "${var.project}-pg"

  engine               = "postgres"
  engine_version       = var.db_engine_version
  family               = "postgres16" 
  major_engine_version = "16"

  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result
  port     = 5432

  multi_az            = var.db_multi_az
  publicly_accessible = false
  deletion_protection = false
  skip_final_snapshot = true

  vpc_security_group_ids = [aws_security_group.rds.id]
  create_db_subnet_group = false
  db_subnet_group_name   = module.vpc.database_subnet_group

  # Recommended minor bits
  maintenance_window  = "Sun:04:00-Sun:05:00"
  backup_window       = "03:00-04:00"
  monitoring_interval = 0

  tags = { Project = var.project }
}

output "rds_endpoint" { value = module.rds.db_instance_endpoint }
output "rds_port" { value = 5432 }
