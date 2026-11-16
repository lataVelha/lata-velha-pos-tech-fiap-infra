# Stories 21.3: SLOs versionados (disponibilidade e latência) por serviço.
#
# SLOs baseados nos monitores existentes (type = "monitor"): a disponibilidade
# mede o tempo em que o monitor de 5xx está OK; a latência mede o tempo em que
# o monitor de p95 está OK. Isso evita duplicar a query e mantém a fonte da
# verdade nos monitores de `monitors.tf`.

resource "datadog_service_level_objective" "availability" {
  for_each = local.trace

  name = "[${var.environment}] ${each.value.service} — disponibilidade 99.5%"
  type = "monitor"

  monitor_ids = [datadog_monitor.http_5xx[each.key].id]

  thresholds {
    timeframe = "30d"
    target    = 99.5
    warning   = 99.9
  }

  tags = concat(local.common_tags, ["service:${each.value.service}", "slo:availability"])
}

resource "datadog_service_level_objective" "latency" {
  for_each = local.trace

  name = "[${var.environment}] ${each.value.service} — p95 dentro do baseline"
  type = "monitor"

  monitor_ids = [datadog_monitor.http_p95[each.key].id]

  thresholds {
    timeframe = "30d"
    target    = 99.0
  }

  tags = concat(local.common_tags, ["service:${each.value.service}", "slo:latency"])
}
