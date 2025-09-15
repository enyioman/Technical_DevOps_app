# Simple VPC with public/private/database subnets + 1 NAT
# Feel free to swap in your existing VPC if you already have one.

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "${var.project}-vpc"
  cidr = "10.20.0.0/16"

  azs             = local.azs
  public_subnets  = ["10.20.0.0/24", "10.20.1.0/24"]
  private_subnets = ["10.20.100.0/24", "10.20.101.0/24"]

  # Separate DB subnets (no NAT/IGW routes)
  database_subnets             = ["10.20.200.0/24", "10.20.201.0/24"]
  create_database_subnet_group = true
  enable_nat_gateway           = true
  single_nat_gateway           = true

  tags = { Project = var.project }
}
