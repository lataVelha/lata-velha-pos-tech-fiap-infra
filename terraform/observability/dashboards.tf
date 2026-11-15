# Dashboard operacional versionado (Stories 18.2, 21.1 e 21.5).
#
# Visão única: APM dos três microsserviços, taxa de erro, p95, JVM, restarts
# e DLQ/profundidade das filas. Filtro global por env.
#
# Story 19.3: o SpanProcessor padroniza o span HTTP server para
# `http.request`; as trace metrics dos 3 serviços EKS são
# `trace.http.request.{hits,errors}` e `p95:trace.http.request`.
# A latência é p95:<prefixo> (a métrica-base é a distribuição de duração,
# em segundos). Não existe <prefixo>.duration.

locals {
  # Story 20.1: as funções serverless têm DD_SERVICE próprio e trace metric
  # root `trace.aws.lambda`, enviada pela Datadog Lambda Extension.
  lambda_services = {
    auth_cpf       = "lata-velha-auth-cpf"
    jwt_authorizer = "lata-velha-jwt-authorizer"
  }
}

resource "datadog_dashboard" "microsservicos" {
  title       = "Lata Velha — Microsserviços"
  description = "APM, erros, latência, JVM, restarts e barramento SQS. Runbook: ${var.runbook_url}"
  layout_type = "ordered"

  template_variable {
    name     = "env"
    prefix   = "env"
    defaults = [var.environment]
  }

  widget {
    note_definition {
      content = <<-EOT
        ## Lata Velha — observabilidade dos microsserviços
        - **EKS (os/inventory/billing):** `trace.http.request.{hits,errors}` e `p95:trace.http.request` (segundos) — naming padronizado na Story 19.3.
        - **Lambdas:** `trace.aws.lambda.{hits,errors}` e `p95:trace.aws.lambda`.
        - **Lambdas:** `lata-velha-auth-cpf` e `lata-velha-jwt-authorizer` usam `trace.aws.lambda.{hits,errors}` e `p95:trace.aws.lambda` (Datadog Lambda Extension).
        - **Restarts:** tags `kube_cluster_name`/`kube_namespace`/`kube_deployment` (o Agent não propaga `service`/`env` nessa métrica).
        - **SQS:** só com a integração AWS habilitada; no AWS Academy use os alarmes CloudWatch do messaging.
        - Runbook: ${var.runbook_url}
      EOT
    }
  }

  # ----------------------------------------------------------------------
  # APM: tráfego, erros e latência
  # ----------------------------------------------------------------------
  widget {
    timeseries_definition {
      title = "Tráfego HTTP (hits/s) por serviço"
      dynamic "request" {
        for_each = local.trace
        content {
          q            = "sum:${request.value.hits}{service:${request.value.service},env:$env}.as_rate()"
          display_type = "line"
        }
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Erros de span/5xx (errors/s) por serviço"
      dynamic "request" {
        for_each = local.trace
        content {
          q            = "sum:${request.value.errors}{service:${request.value.service},env:$env}.as_rate()"
          display_type = "bars"
        }
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Latência p95 (segundos) por serviço"
      dynamic "request" {
        for_each = local.trace
        content {
          q            = "p95:${request.value.latency}{service:${request.value.service},env:$env}"
          display_type = "line"
        }
      }
    }
  }

  # ----------------------------------------------------------------------
  # JVM (métricas OTel coletadas pelo Agent)
  # ----------------------------------------------------------------------
  widget {
    timeseries_definition {
      title = "Heap JVM usado (bytes) por serviço"
      dynamic "request" {
        for_each = local.trace
        content {
          q            = "avg:jvm.heap_memory{service:${request.value.service},env:$env} by {service}"
          display_type = "line"
        }
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Heap JVM máximo (bytes) por serviço"
      dynamic "request" {
        for_each = local.trace
        content {
          q            = "avg:jvm.heap_memory_max{service:${request.value.service},env:$env} by {service}"
          display_type = "line"
        }
      }
    }
  }

  widget {
    timeseries_definition {
      title = "GC JVM — duração (s) por serviço"
      dynamic "request" {
        for_each = local.trace
        content {
          q            = "avg:jvm.gc.duration{service:${request.value.service},env:$env} by {service}"
          display_type = "line"
        }
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Threads JVM por serviço"
      dynamic "request" {
        for_each = local.trace
        content {
          q            = "avg:jvm.thread.count{service:${request.value.service},env:$env} by {service}"
          display_type = "line"
        }
      }
    }
  }

  widget {
    timeseries_definition {
      title = "CPU JVM (fração) por serviço"
      dynamic "request" {
        for_each = local.trace
        content {
          q            = "avg:jvm.cpu.recent_utilization{service:${request.value.service},env:$env} by {service}"
          display_type = "line"
        }
      }
    }
  }

  # ----------------------------------------------------------------------
  # Lambda (Story 20.1): traces/logs da auth-cpf e da jwt-authorizer
  # ----------------------------------------------------------------------
  widget {
    note_definition {
      content = <<-EOT
        ## Lambdas de autenticação
        `lata-velha-auth-cpf` (login por CPF) e `lata-velha-jwt-authorizer`
        (authorizer do API Gateway) enviam traces via Datadog Lambda Extension.
        Queries: `trace.aws.lambda.{hits,errors}` e `p95:trace.aws.lambda`.
      EOT
    }
  }

  widget {
    timeseries_definition {
      title = "Lambda — invocações/s"
      dynamic "request" {
        for_each = local.lambda_services
        content {
          q            = "sum:trace.aws.lambda.hits{service:${request.value},env:$env}.as_rate()"
          display_type = "line"
        }
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Lambda — erros/s"
      dynamic "request" {
        for_each = local.lambda_services
        content {
          q            = "sum:trace.aws.lambda.errors{service:${request.value},env:$env}.as_rate()"
          display_type = "bars"
        }
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Lambda — p95 (segundos)"
      dynamic "request" {
        for_each = local.lambda_services
        content {
          q            = "p95:trace.aws.lambda{service:${request.value},env:$env}"
          display_type = "line"
        }
      }
    }
  }

  # ----------------------------------------------------------------------
  # Kubernetes: restarts
  # ----------------------------------------------------------------------
  widget {
    timeseries_definition {
      title = "Restarts acumulados por pod"
      dynamic "request" {
        for_each = local.trace
        content {
          q            = "max:kubernetes.containers.restarts{kube_cluster_name:${var.kube_cluster_name},kube_namespace:${request.value.namespace},kube_deployment:${request.value.deployment}} by {kube_deployment,pod_name}"
          display_type = "line"
        }
      }
    }
  }

  # ----------------------------------------------------------------------
  # SQS — condicional: a integração AWS não existe no AWS Academy.
  # ----------------------------------------------------------------------
  dynamic "widget" {
    for_each = var.aws_integration_enabled ? [1] : []
    content {
      timeseries_definition {
        title = "Filas SQS — mensagens visíveis"
        request {
          q            = "max:aws.sqs.approximate_number_of_messages_visible{*} by {queuename}"
          display_type = "line"
        }
      }
    }
  }

  dynamic "widget" {
    for_each = var.aws_integration_enabled ? [1] : []
    content {
      timeseries_definition {
        title = "Filas SQS — idade da mensagem mais antiga (s)"
        request {
          q            = "max:aws.sqs.approximate_age_of_oldest_message{*} by {queuename}"
          display_type = "line"
        }
      }
    }
  }

  widget {
    note_definition {
      content = var.aws_integration_enabled ? local.sqs_note_enabled : local.sqs_note_disabled
    }
  }
}
