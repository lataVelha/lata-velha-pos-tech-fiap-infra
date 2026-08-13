output "api_id" {
  value = aws_apigatewayv2_api.this.id
}

output "api_execution_arn" {
  description = "Usado por lambda/app pra montar o source_arn dos próprios recursos"
  value       = aws_apigatewayv2_api.this.execution_arn
}

output "api_endpoint" {
  description = "URL base da API — cada consumidor anexa as próprias rotas"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "vpc_link_id" {
  value = aws_apigatewayv2_vpc_link.this.id
}
