output "app_api_id" {
  value = module.app_gateway.api_id
}

output "app_api_execution_arn" {
  description = "Usado por lambda/app pra montar o source_arn dos próprios recursos"
  value       = module.app_gateway.api_execution_arn
}

output "app_api_endpoint" {
  description = "URL base do API Gateway — cada consumidor anexa as próprias rotas"
  value       = module.app_gateway.api_endpoint
}

output "vpc_link_id" {
  value = module.app_gateway.vpc_link_id
}

output "alb_listener_arn" {
  description = "Usado pelo repo app pra montar a integração HTTP_PROXY"
  value       = module.alb.listener_arn
}

output "alb_dns_name" {
  description = "DNS do ALB — interno, não é a URL pública"
  value       = module.alb.dns_name
}
