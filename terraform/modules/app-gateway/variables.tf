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

variable "alb_listener_arn" {
  description = "ARN do listener HTTP:80 do ALB interno — destino da integracao privada"
  type        = string
}

variable "authorizer_lambda_invoke_arn" {
  description = "invoke_arn da lambda authorizer (repo lambda, output jwt_authorizer_invoke_arn) — usado como authorizer_uri"
  type        = string
}

variable "authorizer_lambda_function_name" {
  description = "Nome da lambda authorizer (repo lambda, output jwt_authorizer_function_name) — usado na aws_lambda_permission"
  type        = string
}

variable "auth_cpf_lambda_invoke_arn" {
  description = "invoke_arn da lambda auth-cpf (repo lambda, output auth_cpf_invoke_arn) — destino da integracao de POST /auth/cpf"
  type        = string
}

variable "auth_cpf_lambda_function_name" {
  description = "Nome da lambda auth-cpf (repo lambda, output auth_cpf_function_name) — usado na aws_lambda_permission"
  type        = string
}

variable "cors_allow_origins" {
  description = "Origens permitidas via CORS na API inteira"
  type        = list(string)
  default     = ["*"]
}

variable "auth_cpf_throttling_rate_limit" {
  description = "Limite de requisicoes/segundo sustentado so na rota POST /auth/cpf — CPF tem baixa entropia"
  type        = number
  default     = 10
}

variable "auth_cpf_throttling_burst_limit" {
  description = "Limite de rajada so na rota POST /auth/cpf"
  type        = number
  default     = 20
}

variable "log_retention_days" {
  description = "Retencao dos logs de acesso no CloudWatch"
  type        = number
  default     = 14
}
