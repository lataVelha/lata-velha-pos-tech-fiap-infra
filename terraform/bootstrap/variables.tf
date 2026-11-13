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
  description = "Quantidade desejada de nodes (minimo de folga para rollout; o autoscaler cresce a partir daqui)"
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Minimo de nodes (nunca menos que 2: com 1 node qualquer rolling update fica sem folga)"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximo de nodes. Precisa suportar os 4 deploys de workload em paralelo (app + os + inventory + billing, 2 replicas cada, 512Mi/pod, maxSurge 1) — 4 nodes (valor antigo) nao cabia e o rollout estourava por pod Pending"
  type        = number
  default     = 8
}

