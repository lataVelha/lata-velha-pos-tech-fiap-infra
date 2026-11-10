variable "region" {
  description = "Região da AWS"
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
  default     = "prod"
}

variable "message_retention_seconds" {
  description = "Retenção das filas principais (4 dias)"
  type        = number
  default     = 345600
}

variable "dlq_message_retention_seconds" {
  description = "Retenção das DLQs (14 dias)"
  type        = number
  default     = 1209600
}

variable "visibility_timeout_seconds" {
  description = "Visibility timeout das filas principais (maior que o pior tempo de processamento conhecido)"
  type        = number
  default     = 120
}

variable "max_receive_count" {
  description = "Quantas entregas antes de mover para a DLQ"
  type        = number
  default     = 5
}

variable "alarm_email" {
  description = "E-mail opcional para receber os alarmes de DLQ/idade de fila"
  type        = string
  default     = ""
}

variable "enable_irsa" {
  description = "Cria roles IRSA por serviço (AWS real). No AWS Academy fica false e o LabRole do node é usado"
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "Nome do EKS cluster (usado para o OIDC provider quando enable_irsa = true)"
  type        = string
  default     = "lata-velha-eks"
}
