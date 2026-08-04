variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "kubernetes_version" {
  description = "Versao do Kubernetes"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets privadas para os nodes"
  type        = list(string)
}

variable "node_instance_type" {
  description = "Tipo das EC2 dos nodes"
  type        = string
}

variable "node_min_size" {
  description = "Minimo de nodes"
  type        = number
}

variable "node_max_size" {
  description = "Maximo de nodes"
  type        = number
}

variable "node_desired_size" {
  description = "Quantidade desejada de nodes"
  type        = number
}

variable "iam_role_arn" {
  description = "ARN da IAM role usada pelo cluster e pelos nodes (ex: LabRole do AWS Academy)"
  type        = string
}

variable "cluster_admin_arns" {
  description = "ARNs de roles/users com acesso admin ao cluster (necessario no AWS Academy)"
  type        = list(string)
  default     = []
}

