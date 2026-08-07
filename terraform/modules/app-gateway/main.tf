# Unico ponto de entrada publico da aplicacao. O ALB (repo infra, modulo
# alb) e interno e so aceita trafego vindo do VPC Link deste API Gateway —
# ninguem alcanca o ALB direto, tudo passa por aqui.

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

# Integracao privada HTTP_PROXY: encaminha metodo/path/headers/body como
# vieram, sem transformacao. payload_format_version precisa ser "1.0" —
# integracoes privadas (VPC_LINK) nao suportam 2.0.
resource "aws_apigatewayv2_integration" "alb" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "HTTP_PROXY"
  integration_uri        = var.alb_listener_arn
  integration_method     = "ANY"
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.this.id
  payload_format_version = "1.0"
}

# Rotas PUBLICAS (sem authorizer) — espelham exatamente os .permitAll() do
# SecurityConfig.java do app.
locals {
  public_routes = [
    "ANY /actuator/health",
    "ANY /actuator/health/{proxy+}",
    "GET /swagger-ui.html",
    "ANY /swagger-ui/{proxy+}",
    "GET /v3/api-docs",
    "ANY /v3/api-docs/{proxy+}",
    "GET /v3/api-docs.yaml",
    "ANY /auth/{proxy+}",
    "POST /ordens-servico/{id}/aprovacao-orcamento",
  ]
}

resource "aws_apigatewayv2_route" "public" {
  for_each  = toset(local.public_routes)
  api_id    = aws_apigatewayv2_api.this.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"
}

# Login por CPF (lambda, repo lambda) — integracao separada, direto na
# lambda (AWS_PROXY), sem passar pelo ALB. Publica de proposito: e o
# endpoint que EMITE o token, entao nao pode exigir a authorizer.
resource "aws_apigatewayv2_integration" "auth_cpf" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.auth_cpf_lambda_invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "auth_cpf" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "POST /auth/cpf"
  target    = "integrations/${aws_apigatewayv2_integration.auth_cpf.id}"
}

resource "aws_lambda_permission" "app_gateway_invoke_auth_cpf" {
  statement_id  = "AllowAppApiGatewayInvokeAuthCpf"
  action        = "lambda:InvokeFunction"
  function_name = var.auth_cpf_lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/POST/auth/cpf"
}

# Lambda authorizer (repo lambda) — duplica na borda a verificacao de
# assinatura/issuer/expiracao do JWT que o app ja faz. Nao decide por role,
# so rejeita cedo tokens invalidos/ausentes antes de gastar um hop ate o
# ALB/pod. Autorizacao por role continua 100% no SecurityConfig do app.
resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id                            = aws_apigatewayv2_api.this.id
  name                              = "${var.project_name}-jwt-authorizer"
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = var.authorizer_lambda_invoke_arn
  identity_sources                  = ["$request.header.Authorization"]
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
  authorizer_result_ttl_in_seconds  = 30
}

resource "aws_lambda_permission" "app_gateway_invoke_authorizer" {
  statement_id  = "AllowAppApiGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = var.authorizer_lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/authorizers/${aws_apigatewayv2_authorizer.jwt.id}"
}

# Rotas PROTEGIDAS — tudo que nao esta na lista publica acima, exigindo a
# authorizer.
resource "aws_apigatewayv2_route" "protected_root" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "ANY /"
  target             = "integrations/${aws_apigatewayv2_integration.alb.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_route" "protected_proxy" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "ANY /{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.alb.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/apigateway/${var.project_name}-app-api"
  retention_in_days = var.log_retention_days
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  # So o login por CPF tem throttle apertado (CPF tem baixa entropia — os
  # digitos verificadores sao calculados, nao aleatorios). O resto da API
  # fica no limite padrao da conta, sem essa restricao.
  route_settings {
    route_key              = aws_apigatewayv2_route.auth_cpf.route_key
    throttling_rate_limit  = var.auth_cpf_throttling_rate_limit
    throttling_burst_limit = var.auth_cpf_throttling_burst_limit
  }

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
