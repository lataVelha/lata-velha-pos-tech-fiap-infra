# Monitores acionáveis da operação (Story 18.1).
#
# Cobertura: DLQ, idade de fila, 5xx, p95, heap da JVM e restarts.
# Cada monitor tem tags service/env/team e mensagem com link do runbook.
#
# Observação: métricas aws.sqs.* exigem a integração AWS instalada no
# Datadog. No AWS Academy (sem integração), os mesmos cenários são cobertos
# pelos alarmes CloudWatch do infra-messaging (alarms.tf), que podem ser
# encaminhados ao Datadog via webhook.

locals {
  notification = join(" ", concat(var.alert_recipients, ["${var.runbook_url}"]))
  common_tags  = ["env:${var.environment}", "team:${var.team}", "managed-by:terraform"]
}

resource "datadog_monitor" "dlq_messages" {
  for_each = var.queues

  name    = "[${var.environment}] DLQ de ${each.value} com mensagens"
  type    = "metric alert"
  message = <<-EOT
    A DLQ `${each.value}` tem mensagens visíveis por mais de 5 minutos.
    Isso significa que um evento falhou 5 vezes e foi movido para a DLQ.

    Runbook: ${var.runbook_url}#4-redrive-da-dlq-para-a-fila-principal
    ${local.notification}
  EOT

  query = "max(last_5m):max:aws.sqs.approximate_number_of_messages_visible{queuename:${each.value}-dlq} > 0"

  monitor_thresholds {
    critical = 0
  }

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.common_tags, ["service:${each.value}"])
}

resource "datadog_monitor" "queue_age" {
  for_each = var.queues

  name    = "[${var.environment}] Fila ${each.value} envelhecendo"
  type    = "metric alert"
  message = <<-EOT
    A mensagem mais antiga da fila `${each.value}` passou de 300s.
    Consumidor atrasado ou parado — verifique o Deployment e os logs.

    Runbook: ${var.runbook_url}#2-inspeção
    ${local.notification}
  EOT

  query = "max(last_5m):max:aws.sqs.approximate_age_of_oldest_message{queuename:${each.value}} > 300"

  monitor_thresholds {
    critical = 300
    warning  = 180
  }

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.common_tags, ["service:${each.value}"])
}

resource "datadog_monitor" "http_5xx" {
  for_each = var.services

  name    = "[${var.environment}] ${each.value} — 5xx > 1%"
  type    = "metric alert"
  message = <<-EOT
    Taxa de erros 5xx do serviço `${each.value}` acima de 1% por 5 minutos.

    Runbook: ${var.runbook_url}#3-serviço-sem-telemetria
    ${local.notification}
  EOT

  query = "sum(last_5m):sum:trace.http.request.errors{service:${each.value},env:${var.environment}}.as_rate() / sum:trace.http.request.hits{service:${each.value},env:${var.environment}}.as_rate() > 0.01"

  monitor_thresholds {
    critical = 0.01
    warning  = 0.005
  }

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.common_tags, ["service:${each.value}"])
}

resource "datadog_monitor" "http_p95" {
  for_each = var.services

  name    = "[${var.environment}] ${each.value} — p95 acima do baseline"
  type    = "metric alert"
  message = <<-EOT
    Latência p95 do serviço `${each.value}` passou de ${lookup(var.p95_baseline_ms, each.value, 1000)}ms.

    Runbook: ${var.runbook_url}#5-latência-e-erros
    ${local.notification}
  EOT

  query = "p95(last_10m):p95:trace.http.request.duration{service:${each.value},env:${var.environment}} > ${lookup(var.p95_baseline_ms, each.value, 1000)}"

  monitor_thresholds {
    critical = lookup(var.p95_baseline_ms, each.value, 1000)
  }

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.common_tags, ["service:${each.value}"])
}

resource "datadog_monitor" "jvm_heap" {
  for_each = var.services

  name    = "[${var.environment}] ${each.value} — heap JVM > 85%"
  type    = "metric alert"
  message = <<-EOT
    Heap da JVM do serviço `${each.value}` acima de 85% — risco de OOM/CrashLoop.

    Runbook: ${var.runbook_url}#6-jvm-e-restarts
    ${local.notification}
  EOT

  query = "avg(last_10m):avg:jvm.heap_memory{service:${each.value},env:${var.environment}} / avg:jvm.heap_memory_max{service:${each.value},env:${var.environment}} > 0.85"

  monitor_thresholds {
    critical = 0.85
    warning  = 0.75
  }

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.common_tags, ["service:${each.value}"])
}

resource "datadog_monitor" "pod_restarts" {
  for_each = var.services

  name    = "[${var.environment}] ${each.value} — mais de 3 restarts em 15 min"
  type    = "metric alert"
  message = <<-EOT
    O serviço `${each.value}` reiniciou mais de 3 vezes em 15 minutos.

    Runbook: ${var.runbook_url}#6-jvm-e-restarts
    ${local.notification}
  EOT

  query = "sum(last_15m):sum:kubernetes.containers.restarts{service:${each.value},env:${var.environment}}.increase() > 3"

  monitor_thresholds {
    critical = 3
  }

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.common_tags, ["service:${each.value}"])
}
