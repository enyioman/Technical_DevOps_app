variable "cluster_version" {
  type    = string
  default = "1.29"
}

variable "node_desired_size" {
  type    = number
  default = 2
}
variable "node_min_size" {
  type    = number
  default = 2
}
variable "node_max_size" {
  type    = number
  default = 5
}
variable "node_instance_types" {
  type    = list(string)
  default = ["t2.medium"]
}


module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.33.0"

  cluster_name                             = "${var.project}-eks"
  cluster_version                          = var.cluster_version
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Managed node group
  eks_managed_node_groups = {
    default = {
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
      instance_types = var.node_instance_types
      subnet_ids     = module.vpc.private_subnets
      tags           = { Project = var.project }
    }
  }

  tags = { Project = var.project }
}

# Expose cluster connection details to providers
data "aws_eks_cluster" "this" {
  name = module.eks.cluster_name
  depends_on = [module.eks]
}
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
  depends_on = [module.eks]
}

# (Optional) Write your kubeconfig context locally after apply.
# Requires AWS CLI installed where you run Terraform.
resource "null_resource" "kubeconfig" {
  triggers = {
    cluster_name = module.eks.cluster_name
    region       = var.region
  }
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region} --alias ${var.project}-eks"
  }
  depends_on = [module.eks]
}

output "eks_cluster_name" { value = module.eks.cluster_name }
output "eks_kubeconfig_hint" { value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region} --alias ${var.project}-eks" }
