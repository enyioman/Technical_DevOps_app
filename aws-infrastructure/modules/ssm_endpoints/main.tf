variable "project" { type = string }
variable "aws_region" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "private_route_table_ids" { type = list(string) } # for S3 gateway endpoint
variable "instance_sg_id" { type = string }
variable "allowed_cidrs" {
  type    = list(string)
  default = []
}
variable "create_s3_gateway" {
  type    = bool
  default = false
}

data "aws_region" "current" {}

resource "aws_security_group" "ssm_endpoints" {
  name   = "${var.project}-ssm-endpoints-sg"
  vpc_id = var.vpc_id
  ingress {
    description     = "TLS from your VPC/instances"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [var.instance_sg_id]
    cidr_blocks     = length(var.allowed_cidrs) > 0 ? var.allowed_cidrs : ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Interface endpoints for Session Manager
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.ssm_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.ssm_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.ssm_endpoints.id]
  private_dns_enabled = true
}

# Secrets Manager interface endpoint
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.ssm_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "s3" {
  count             = var.create_s3_gateway ? 1 : 0
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids
}


output "endpoint_sg_id" { value = aws_security_group.ssm_endpoints.id }
output "ssm_id" { value = aws_vpc_endpoint.ssm.id }
output "ec2msg_id" { value = aws_vpc_endpoint.ec2messages.id }
output "ssmmsg_id" { value = aws_vpc_endpoint.ssmmessages.id }
output "s3_id" { value = try(aws_vpc_endpoint.s3[0].id, null) }
