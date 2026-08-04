output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "cluster_security_group_id" {
  value = module.eks.cluster_security_group_id
}

output "node_asg_name" {
  value = module.eks.node_asg_name
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr" {
  value = var.vpc_cidr
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Usado pelo repo infra-db para provisionar o RDS nesta VPC"
  value       = module.vpc.private_subnet_ids
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "kubernetes_version" {
  value = var.kubernetes_version
}
