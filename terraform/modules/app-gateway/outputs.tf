output "api_id" {
  value = aws_apigatewayv2_api.this.id
}

output "api_execution_arn" {
  description = "execution_arn da API — usado pelos repos lambda/app pra montar o source_arn dos aws_lambda_permission/integrations que eles anexam aqui de fora"
  value       = aws_apigatewayv2_api.this.execution_arn
}

output "api_endpoint" {
  description = "URL base da API (sem rotas ainda — cada consumidor anexa as proprias)"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "vpc_link_id" {
  value = aws_apigatewayv2_vpc_link.this.id
}
