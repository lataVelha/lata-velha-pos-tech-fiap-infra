# Story 21.3: synthetic tests versionados.
#
# Dois testes públicos (sem dados sensíveis):
#   1. GET /actuator/health — borda -> ALB -> os-service
#   2. GET /auth/cpf-openapi.json — borda -> Lambda auth-cpf
#
# O `app_api_url` vem do output do stack addons e é passado pelo pipeline.
# Quando vazio (apply local sem URL), os testes não são criados.

resource "datadog_synthetics_test" "health" {
  count = var.app_api_url == "" ? 0 : 1

  name    = "[${var.environment}] API pública — health"
  type    = "api"
  subtype = "http"
  status  = "live"
  message = "Health público fora do ar. Runbook: ${var.runbook_url}"

  request_definition {
    method  = "GET"
    url     = "${trimsuffix(var.app_api_url, "/")}/actuator/health"
    timeout = 30
  }

  assertion {
    type     = "statusCode"
    operator = "is"
    target   = "200"
  }

  assertion {
    type     = "body"
    operator = "contains"
    target   = "UP"
  }

  locations = ["aws:us-east-1"]

  options_list {
    tick_every = 300

    retry {
      count    = 2
      interval = 300
    }

    monitor_options {
      renotify_interval = 0
    }
  }

  tags = concat(local.common_tags, ["service:lata-velha-os-service", "synthetic:health"])
}

resource "datadog_synthetics_test" "auth_openapi" {
  count = var.app_api_url == "" ? 0 : 1

  name    = "[${var.environment}] API pública — OpenAPI da auth-cpf"
  type    = "api"
  subtype = "http"
  status  = "live"
  message = "OpenAPI público da auth-cpf fora do ar (Lambda). Runbook: ${var.runbook_url}"

  request_definition {
    method  = "GET"
    url     = "${trimsuffix(var.app_api_url, "/")}/auth/cpf-openapi.json"
    timeout = 30
  }

  assertion {
    type     = "statusCode"
    operator = "is"
    target   = "200"
  }

  assertion {
    type     = "body"
    operator = "contains"
    target   = "paths"
  }

  locations = ["aws:us-east-1"]

  options_list {
    tick_every = 300

    retry {
      count    = 2
      interval = 300
    }

    monitor_options {
      renotify_interval = 0
    }
  }

  tags = concat(local.common_tags, ["service:lata-velha-auth-cpf", "synthetic:auth-openapi"])
}
