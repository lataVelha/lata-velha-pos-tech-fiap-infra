variable "region" {
  description = "Regiao da AWS"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefixo dos recursos"
  type        = string
  default     = "lata-velha"
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "kubernetes_version" {
  description = "Versao do Kubernetes no EKS"
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  description = "Tipo das EC2 dos nodes"
  type        = string
  default     = "t3.small"
}

variable "node_desired_size" {
  description = "Quantidade desejada de nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimo de nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximo de nodes (deve suportar o maxReplicas do HPA)"
  type        = number
  default     = 4
}

