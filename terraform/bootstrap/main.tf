data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  cluster_name    = "${var.project_name}-eks"
  caller_arn      = data.aws_caller_identity.current.arn
  is_assumed_role = can(regex(":assumed-role/", local.caller_arn))
  role_name       = local.is_assumed_role ? split("/", split(":", local.caller_arn)[5])[1] : ""
  admin_arn       = local.is_assumed_role ? "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.role_name}" : local.caller_arn
  lab_role_arn    = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
}

module "vpc" {
  source = "../modules/vpc"

  name               = var.project_name
  vpc_cidr           = var.vpc_cidr
  azs                = slice(data.aws_availability_zones.available.names, 0, 2)
  enable_nat_gateway = true
  cluster_name       = local.cluster_name
}

module "eks" {
  source = "../modules/eks"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version
  subnet_ids         = module.vpc.private_subnet_ids
  node_instance_type = var.node_instance_type
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
  node_desired_size  = var.node_desired_size
  iam_role_arn       = local.lab_role_arn
  cluster_admin_arns = [local.admin_arn]

  depends_on = [module.vpc]
}

# O ECR do monolito (`lata-velha`) foi removido junto com o repo `app`.
# Cada microsservico provisiona o proprio repositorio ECR no seu state
# (os-service, inventory-service e billing-service).

