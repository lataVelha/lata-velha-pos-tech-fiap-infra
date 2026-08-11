variable "project_name" {
  description = "Prefixo dos recursos"
  type        = string
}

variable "vpc_link_subnet_ids" {
  description = "Subnets privadas onde os ENIs do VPC Link sao criados — mesmas do ALB"
  type        = list(string)
}

variable "vpc_link_security_group_id" {
  description = "Security group dos ENIs do VPC Link — precisa ser o mesmo liberado no SG do ALB"
  type        = string
}

variable "cors_allow_origins" {
  description = "Origens permitidas via CORS na API inteira"
  type        = list(string)
  default     = ["*"]
}

variable "log_retention_days" {
  description = "Retencao dos logs de acesso no CloudWatch"
  type        = number
  default     = 14
}
