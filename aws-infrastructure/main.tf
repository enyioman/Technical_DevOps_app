locals { name = var.project }

module "vpc" {
  source   = "./modules/vpc"
  name     = local.name
  vpc_cidr = var.vpc_cidr
  az_count = var.az_count
}

module "s3" {
  source        = "./modules/s3"
  project       = local.name
  static_bucket = var.static_bucket_name
  logs_bucket   = var.logs_bucket_name
  # alb_account_arn = "*" # generic
  region = var.aws_region
}

module "iam" {
  source            = "./modules/iam"
  project           = local.name
  static_bucket_arn = module.s3.static_bucket_arn
}

module "rds" {
  source             = "./modules/rds"
  project            = local.name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  db_name            = var.db_name
  db_user            = var.db_user
  db_port            = var.db_port
  instance_class     = var.db_instance_class
  storage            = var.db_allocated_storage
  multi_az           = var.multi_az
  db_password        = random_password.dbpass.result
}

module "alb" {
  source            = "./modules/alb"
  project           = local.name
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  logs_bucket       = var.logs_bucket_name
}

module "asg" {
  source               = "./modules/asg"
  project              = local.name
  aws_region           = var.aws_region
  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.private_subnet_ids
  target_group_arn     = module.alb.target_group_arn
  instance_type        = var.instance_type
  key_name             = var.key_name
  iam_instance_profile = module.iam.instance_profile_name
  app_repo_url         = var.app_repo_url
  app_branch           = var.app_branch
  allowed_hosts        = var.allowed_hosts
  static_bucket_name   = var.static_bucket_name
  secrets_name         = aws_secretsmanager_secret.db.name
  alb_sg_id            = module.alb.alb_sg_id
  django_secret_key    = var.django_secret_key

  # sizes: 2 total, spread across AZs
  min_size         = 2
  desired_capacity = 2
  max_size         = 2
}

# locals {
#   # map like {"0" = <sg-id-from-asg0>, "1" = <sg-id-from-asg1>, ...}
#   asg_sg_ids = { for idx, m in module.asg : tostring(idx) => m.ec2_sg_id }
# }

# Secrets Manager for DB creds (json: {username,password,host,port,dbname})
resource "random_password" "dbpass" {
  length  = 20
  special = false
}
resource "aws_secretsmanager_secret" "db" {
  name = "${local.name}-db-secret"
}
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_user,
    password = random_password.dbpass.result,
    host     = module.rds.db_endpoint,
    port     = var.db_port,
    dbname   = var.db_name
  })
}

# Now that ASG SG exists, permit it into RDS
resource "aws_security_group_rule" "rds_ingress" {
  type                     = "ingress"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  security_group_id        = module.rds.rds_sg_id
  source_security_group_id = module.asg.ec2_sg_id
}

module "cloudwatch" {
  source         = "./modules/cloudwatch"
  project        = local.name
  alb_arn_suffix = module.alb.alb_arn_suffix
  asg_names      = module.asg.asg_name
  alert_email    = var.alert_email
}

module "ssm_endpoints" {
  source                  = "./modules/ssm_endpoints"
  project                 = var.project
  aws_region              = var.aws_region
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  private_route_table_ids = [module.vpc.private_route_table_id] # see note below
  allowed_cidrs           = [var.vpc_cidr]                      # or module.vpc.vpc_cidr if you output it
  instance_sg_id          = module.asg.ec2_sg_id
  create_s3_gateway       = true
}

locals {
  allowed_hosts_computed = join(",", [
    module.alb.alb_dns_name,
    "localhost",
    "127.0.0.1"
  ])
}

module "ssm_bootstrap" {
  source             = "./modules/ssm_bootstrap"
  project            = var.project
  region             = var.aws_region
  asg_name           = module.asg.asg_name
  app_repo_url       = var.app_repo_url
  app_branch         = var.app_branch
  allowed_hosts      = local.allowed_hosts_computed
  secret_name        = aws_secretsmanager_secret.db.name
  static_bucket_name = var.static_bucket_name
  wsgi_module        = "mysite.wsgi:application"


  depends_on = [
    module.asg,
    aws_secretsmanager_secret_version.db
  ]
}
