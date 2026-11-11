output "api_endpoint" {
  description = "URL publica da API (API Gateway compartilhado)"
  value       = local.addons.app_api_endpoint
}

output "integration_id" {
  description = "ID da integracao HTTP_PROXY com o ALB"
  value       = aws_apigatewayv2_integration.alb.id
}

output "route_keys" {
  description = "Rotas gerenciadas por este stack"
  value = concat(
    local.public_routes,
    ["ANY /", "ANY /{proxy+}"],
  )
}
