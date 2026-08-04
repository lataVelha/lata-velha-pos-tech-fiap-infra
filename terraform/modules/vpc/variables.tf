variable "name" {
  description = "Prefixo de nome"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR da VPC"
  type        = string
}

variable "azs" {
  description = "Zonas de disponibilidade"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Cria NAT Gateway (~US$32/mes). Necessario para nodes privados do EKS."
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "Nome do cluster EKS, usado nas tags das subnets. Vazio = nao aplica a tag."
  type        = string
  default     = ""
}
