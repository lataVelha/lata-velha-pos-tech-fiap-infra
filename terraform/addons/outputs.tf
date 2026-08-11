output "app_api_id" {
  value = module.app_gateway.api_id
}

output "app_api_execution_arn" {
  description = "execution_arn do API Gateway — lido pelos repos lambda/app pra montar o source_arn dos aws_lambda_permission/integrations que eles anexam"
  value       = module.app_gateway.api_execution_arn
}

output "app_api_endpoint" {
  description = "URL base do API Gateway (sem rotas ainda — cada consumidor anexa as proprias: repo lambda anexa /auth/cpf, repo app anexa o resto)"
  value       = module.app_gateway.api_endpoint
}

output "vpc_link_id" {
  value = module.app_gateway.vpc_link_id
}

output "alb_listener_arn" {
  description = "ARN do listener HTTP:80 do ALB interno — lido pelo repo app pra montar a propria integracao HTTP_PROXY com o API Gateway"
  value       = module.alb.listener_arn
}

output "alb_dns_name" {
  description = "DNS name do ALB — interno, so resolve/e alcancavel de dentro da VPC. Nao e a URL publica"
  value       = module.alb.dns_name
}
