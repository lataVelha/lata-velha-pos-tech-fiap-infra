# Recurso compartilhado do API Gateway: so o "casco" fica aqui (API + VPC
# Link + Stage + log group). Quem usa anexa as proprias rotas/integracoes
# via terraform_remote_state — repo lambda anexa POST /auth/cpf + a
# authorizer, repo app anexa a integracao com o ALB + as rotas publicas e
# protegidas. Assim este modulo nao depende de nenhum dos dois pra ser
# aplicado, e roda logo em seguida do bootstrap, sem esperar mais nada.

resource "aws_apigatewayv2_api" "this" {
  name          = "${var.project_name}-app-api"
  protocol_type = "HTTP"
  description   = "Entrada publica unica da aplicacao Lata Velha — proxy privado (VPC Link) para o ALB interno, mais a rota de login por CPF (lambda)"

  cors_configuration {
    allow_origins = var.cors_allow_origins
    allow_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers = ["content-type", "authorization"]
  }
}

resource "aws_apigatewayv2_vpc_link" "this" {
  name               = "${var.project_name}-app-vpc-link"
  security_group_ids = [var.vpc_link_security_group_id]
  subnet_ids         = var.vpc_link_subnet_ids
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/apigateway/${var.project_name}-app-api"
  retention_in_days = var.log_retention_days
}

# auto_deploy=true: qualquer rota anexada depois (pelos repos lambda/app) e
# publicada automaticamente, sem precisar reaplicar este modulo. O throttle
# por rota que existia aqui pro POST /auth/cpf saiu daqui — este modulo nao
# conhece mais nenhuma rota especifica pra configurar isso. Se precisar
# recuperar rate-limit no login por CPF, fazer via WAFv2 (rate-based rule
# por path) em vez de route_settings.
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.this.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      httpMethod       = "$context.httpMethod"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }
}
