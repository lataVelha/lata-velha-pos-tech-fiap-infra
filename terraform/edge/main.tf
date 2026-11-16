# Borda unica da API: integracao do API Gateway compartilhado com o ALB
# interno + rotas publicas/protegidas. Antes esse conjunto vivia no stack do
# app; com o cutover ele passa a ter um dono unico (este stack), aplicado
# depois do lambda (authorizer) e do app (quando presente).
#
# O ALB faz o roteamento por path (target groups/listener rules em
# terraform/addons). Aqui so decidimos autorizacao:
#   - rotas publicas: sem authorizer
#   - ANY / e ANY /{proxy+}: CUSTOM authorizer (JWT do repo lambda)

data "terraform_remote_state" "addons" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = var.addons_state_key
    region = var.region
  }
}

# jwt_authorizer_id — anexado pelo repo lambda no mesmo API Gateway.
data "terraform_remote_state" "lambda" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = var.lambda_state_key
    region = var.region
  }
}

locals {
  addons = data.terraform_remote_state.addons.outputs
  lambda = data.terraform_remote_state.lambda.outputs

  # Rotas PUBLICAS (sem authorizer) — espelham exatamente os .permitAll()
  # dos SecurityConfig dos servicos.
  public_routes = [
    "ANY /actuator/health",
    "ANY /actuator/health/{proxy+}",
    # os-service swagger
    "GET /swagger-ui.html",
    "ANY /swagger-ui/{proxy+}",
    "GET /v3/api-docs",
    "ANY /v3/api-docs/{proxy+}",
    "GET /v3/api-docs.yaml",
    # billing-service swagger
    "GET /billing/swagger-ui.html",
    "ANY /billing/swagger-ui/{proxy+}",
    "GET /billing/v3/api-docs",
    "ANY /billing/v3/api-docs/{proxy+}",
    # inventory-service swagger
    "GET /inventory/swagger-ui.html",
    "ANY /inventory/swagger-ui/{proxy+}",
    "GET /inventory/v3/api-docs",
    "ANY /inventory/v3/api-docs/{proxy+}",
    # os-service login — rota publica (sem JWT ainda para obter o token).
    "POST /auth/login",
    # lambda auth-cpf: rotas de swagger e openapi criadas diretamente no repo
    # lambda (apontam para integracao Lambda, nao ALB). Sem rota /auth/ aqui.
    # Webhook do Mercado Pago — chamado pela plataforma sem token JWT.
    "POST /pagamentos/webhook",
    "POST /ordens-servico/{id}/aprovacao-orcamento",
  ]
}

# payload_format_version precisa ser "1.0" — integracoes privadas (VPC_LINK)
# nao suportam 2.0.
resource "aws_apigatewayv2_integration" "alb" {
  api_id                 = local.addons.app_api_id
  integration_type       = "HTTP_PROXY"
  integration_uri        = local.addons.alb_listener_arn
  integration_method     = "ANY"
  connection_type        = "VPC_LINK"
  connection_id          = local.addons.vpc_link_id
  payload_format_version = "1.0"
}

# Integração das rotas PROTEGIDAS: repassa o traceparent devolvido pelo
# authorizer JWT no context. O API Gateway não injeta W3C sozinho; sem isso
# o ALB/EKS recebe a requisição sem traceparent e o Spring Boot OTel abre um
# novo trace raiz (flow map partido entre edge e micros).
# Fica separada da integração pública porque `$context.authorizer.*` não
# existe nas rotas sem authorizer.
resource "aws_apigatewayv2_integration" "alb_traced" {
  api_id                 = local.addons.app_api_id
  integration_type       = "HTTP_PROXY"
  integration_uri        = local.addons.alb_listener_arn
  integration_method     = "ANY"
  connection_type        = "VPC_LINK"
  connection_id          = local.addons.vpc_link_id
  payload_format_version = "1.0"

  request_parameters = {
    "overwrite:header.traceparent" = "$context.authorizer.traceparent"
  }
}

resource "aws_apigatewayv2_route" "public" {
  for_each = toset(local.public_routes)

  api_id    = local.addons.app_api_id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"
}

# Rotas PROTEGIDAS — tudo que nao esta na lista publica acima.
resource "aws_apigatewayv2_route" "protected_root" {
  api_id             = local.addons.app_api_id
  route_key          = "ANY /"
  target             = "integrations/${aws_apigatewayv2_integration.alb_traced.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = local.lambda.jwt_authorizer_id
}

resource "aws_apigatewayv2_route" "protected_proxy" {
  api_id             = local.addons.app_api_id
  route_key          = "ANY /{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.alb_traced.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = local.lambda.jwt_authorizer_id
}
