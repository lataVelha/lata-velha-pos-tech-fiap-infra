# Monitores acionáveis da operação (Stories 18.1, 21.1, 21.3 e 21.5).
#
# Cobertura: DLQ, idade de fila, 5xx, p95, heap da JVM e restarts.
# Cada monitor tem tags service/env/team/managed-by e mensagem com link do runbook.
#
# Métricas reais deste setup OTel (ver locals.tf):
#   os/inventory -> trace.org.springframework.boot.server.{hits,errors}
#   billing      -> trace.io.opentelemetry.spring_webmvc_6.0.server.{hits,errors}
#   latência     -> p95:<prefixo> em SEGUNDOS (não existe .duration)
#
# Observação: métricas aws.sqs.* exigem a integração AWS instalada no
# Datadog. No AWS Academy (sem integração), os monitores de fila não são
# criados; os mesmos cenários são cobertos pelos alarmes CloudWatch do
# infra-messaging (alarms.tf).

resource "datadog_monitor" "dlq_messages" {
  for_each = var.aws_integration_enabled ? var.queues : {}

  name    = "[${var.environment}] DLQ de ${each.value} com mensagens"
  type    = "metric alert"
  message = <<-EOT
    A DLQ `${each.value}` tem mensagens visíveis por mais de 5 minutos.
    Isso significa que um evento falhou 5 vezes e foi movido para a DLQ.

    Runbook: ${var.runbook_url}#7-dlq--filas
    ${local.notification}
  EOT

  query = "max(last_5m):max:aws.sqs.approximate_number_of_messages_visible{queuename:${each.value}-dlq} > 0"

  monitor_thresholds {
    critical = 0
  }

  require_full_window = false
  on_missing_data     = "resolve"
  tags                = concat(local.common_tags, ["service:${each.value}", "integration:aws"])
}

resource "datadog_monitor" "queue_age" {
  for_each = var.aws_integration_enabled ? var.queues : {}

  name    = "[${var.environment}] Fila ${each.value} envelhecendo"
  type    = "metric alert"
  message = <<-EOT
    A mensagem mais antiga da fila `${each.value}` passou de 300s.
    Consumidor atrasado ou parado — verifique o Deployment e os logs.

    Runbook: ${var.runbook_url}#7-dlq--filas
    ${local.notification}
  EOT

  query = "max(last_5m):max:aws.sqs.approximate_age_of_oldest_message{queuename:${each.value}} > 300"

  monitor_thresholds {
    critical = 300
    warning  = 180
  }

  require_full_window = false
  on_missing_data     = "resolve"
  tags                = concat(local.common_tags, ["service:${each.value}", "integration:aws"])
}

resource "datadog_monitor" "http_5xx" {
  for_each = local.trace

  name    = "[${var.environment}] ${each.value.service} — erros 5xx > 1%"
  type    = "metric alert"
  message = <<-EOT
    Taxa de erros 5xx do serviço `${each.value.service}` acima de 1% por 5 minutos.
    A métrica `${each.value.errors}` conta spans HTTP server marcados como erro
    (5xx e falhas internas); 4xx é validado como não-erro neste setup.

    Runbook: ${var.runbook_url}#5-latência-e-erros
    ${local.notification}
  EOT

  query = "sum(last_5m):sum:${each.value.errors}{service:${each.value.service},env:${var.environment}}.as_rate() / sum:${each.value.hits}{service:${each.value.service},env:${var.environment}}.as_rate() > 0.01"

  monitor_thresholds {
    critical = 0.01
    warning  = 0.005
  }

  require_full_window = false
  on_missing_data     = "resolve"
  tags                = concat(local.common_tags, ["service:${each.value.service}"])
}

resource "datadog_monitor" "http_p95" {
  for_each = local.trace

  name    = "[${var.environment}] ${each.value.service} — p95 acima do baseline"
  type    = "metric alert"
  message = <<-EOT
    Latência p95 do serviço `${each.value.service}` passou de
    ${lookup(var.p95_baseline_ms, each.value.service, 1000)}ms.
    A métrica real é `p95:${each.value.latency}` em segundos.

    Runbook: ${var.runbook_url}#5-latência-e-erros
    ${local.notification}
  EOT

  query = "avg(last_10m):p95:${each.value.latency}{service:${each.value.service},env:${var.environment}} > ${lookup(local.p95_baseline_seconds, each.value.service, 1)}"

  monitor_thresholds {
    critical = lookup(local.p95_baseline_seconds, each.value.service, 1)
  }

  require_full_window = false
  on_missing_data     = "resolve"
  tags                = concat(local.common_tags, ["service:${each.value.service}"])
}

resource "datadog_monitor" "jvm_heap" {
  for_each = local.trace

  name    = "[${var.environment}] ${each.value.service} — heap JVM > 85%"
  type    = "metric alert"
  message = <<-EOT
    Heap da JVM do serviço `${each.value.service}` acima de 85% — risco de OOM/CrashLoop.

    Runbook: ${var.runbook_url}#6-jvm-e-restarts
    ${local.notification}
  EOT

  query = "avg(last_10m):avg:jvm.heap_memory{service:${each.value.service},env:${var.environment}} / avg:jvm.heap_memory_max{service:${each.value.service},env:${var.environment}} > 0.85"

  monitor_thresholds {
    critical = 0.85
    warning  = 0.75
  }

  require_full_window = false
  on_missing_data     = "resolve"
  tags                = concat(local.common_tags, ["service:${each.value.service}"])
}

resource "datadog_monitor" "pod_restarts" {
  for_each = local.trace

  name    = "[${var.environment}] ${each.value.service} — mais de 3 restarts em 15 min"
  type    = "metric alert"
  message = <<-EOT
    O serviço `${each.value.service}` reiniciou mais de 3 vezes em 15 minutos
    (namespace `${each.value.namespace}`, deployment `${each.value.deployment}`).

    Runbook: ${var.runbook_url}#6-jvm-e-restarts
    ${local.notification}
  EOT

  query = "max(last_15m):max:kubernetes.containers.restarts{kube_cluster_name:${var.kube_cluster_name},kube_namespace:${each.value.namespace},kube_deployment:${each.value.deployment}} > 3"

  monitor_thresholds {
    critical = 3
  }

  require_full_window = false
  on_missing_data     = "resolve"
  tags                = concat(local.common_tags, ["service:${each.value.service}"])
}
