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
  default     = "prod"
}

variable "state_bucket" {
  description = "Bucket S3 com os states do bootstrap/addons/lambda"
  type        = string
}

variable "addons_state_key" {
  description = "Chave do state do repo infra (addons) — API Gateway + ALB"
  type        = string
  default     = "lata-velha/infra-addons/terraform.tfstate"
}

variable "lambda_state_key" {
  description = "Chave do state do repo lambda — jwt_authorizer_id"
  type        = string
  default     = "lata-velha/lambda-auth-cpf/terraform.tfstate"
}
