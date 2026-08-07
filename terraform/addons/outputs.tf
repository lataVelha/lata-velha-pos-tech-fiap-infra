output "app_api_endpoint" {
  description = "URL publica da aplicacao — ponto de entrada unico (API Gateway -> VPC Link -> ALB interno)"
  value       = module.app_gateway.api_endpoint
}

output "app_api_id" {
  value = module.app_gateway.api_id
}

output "auth_cpf_endpoint" {
  description = "URL do login por CPF — mesma base do app_api_endpoint, path /auth/cpf"
  value       = module.app_gateway.auth_cpf_endpoint
}

output "alb_dns_name" {
  description = "DNS name do ALB — interno, so resolve/e alcancavel de dentro da VPC. Nao e mais a URL publica"
  value       = module.alb.dns_name
}
