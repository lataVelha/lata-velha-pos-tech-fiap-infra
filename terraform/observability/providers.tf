provider "datadog" {
  api_key = var.dd_api_key
  app_key = var.dd_app_key
  api_url = var.dd_api_url
}

# Story 20.3: o fallback CloudWatch -> Datadog Events usa EventBridge.
# A integração AWS nativa continua controlada por `aws_integration_enabled`;
# este provider só existe para o caminho de fallback (e para o account ID).
provider "aws" {
  region = var.aws_region

  # O job de validação (terraform validate) roda sem credenciais AWS.
  # O plan/apply do pipeline usa credenciais reais.
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}
