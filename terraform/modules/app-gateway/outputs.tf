output "api_endpoint" {
  description = "URL publica da aplicacao (substitui o acesso direto ao ALB)"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "api_id" {
  value = aws_apigatewayv2_api.this.id
}

output "auth_cpf_endpoint" {
  description = "URL do login por CPF (POST {auth_cpf_endpoint} com {\"cpf\": \"...\"}) — mesma base do api_endpoint"
  value       = "${aws_apigatewayv2_stage.default.invoke_url}auth/cpf"
}
