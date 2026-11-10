# Dashboard operacional versionado (Story 18.2).
#
# Visão única: APM dos quatro serviços, taxa de erro, p95, tráfego, JVM,
# DLQ e profundidade das filas. Filtro global por env.

locals {
  dashboard_service_template = join(" OR ", [
    for name in values(var.services) : "service:${name}"
  ])
}

resource "datadog_dashboard" "microsservicos" {
  title       = "Lata Velha — Microsserviços"
  description = "APM, erros, latência, JVM e barramento SQS. Runbook: ${var.runbook_url}"
  layout_type = "ordered"

  template_variable {
    name    = "env"
    prefix  = "env"
    default = var.environment
  }

  widget {
    timeseries_definition {
      title = "Tráfego HTTP (hits/s) por serviço"
      request {
        q            = "sum:trace.http.request.hits{${local.dashboard_service_template}} by {service}.as_rate()"
        display_type = "line"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Erros 5xx por serviço"
      request {
        q            = "sum:trace.http.request.errors{${local.dashboard_service_template}} by {service}.as_rate()"
        display_type = "bars"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Latência p95 (ms) por serviço"
      request {
        q            = "p95:trace.http.request.duration{${local.dashboard_service_template}} by {service}"
        display_type = "line"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Heap JVM usado por serviço"
      request {
        q            = "avg:jvm.heap_memory{${local.dashboard_service_template}} by {service}"
        display_type = "line"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "GC / threads da JVM"
      request {
        q            = "avg:jvm.gc.parnew.time{${local.dashboard_service_template}} by {service}"
        display_type = "line"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Filas SQS — mensagens visíveis"
      request {
        q            = "max:aws.sqs.approximate_number_of_messages_visible{*} by {queuename}"
        display_type = "line"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Filas SQS — idade da mensagem mais antiga (s)"
      request {
        q            = "max:aws.sqs.approximate_age_of_oldest_message{*} by {queuename}"
        display_type = "line"
      }
    }
  }

  widget {
    toplist_definition {
      title = "Top serviços por erros (1h)"
      request {
        q = "top(sum:trace.http.request.errors{${local.dashboard_service_template}} by {service}, 10, 'sum', 'desc')"
      }
    }
  }

  widget {
    note_definition {
      content = <<-EOT
        ## Runbook
        - Serviço sem telemetria: ${var.runbook_url}#3-serviço-sem-telemetria
        - DLQ: ${var.runbook_url}#4-redrive-da-dlq-para-a-fila-principal
        - JVM/restarts: ${var.runbook_url}#6-jvm-e-restarts
      EOT
    }
  }
}
