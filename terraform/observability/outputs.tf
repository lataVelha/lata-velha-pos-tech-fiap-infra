output "dashboard_id" {
  description = "ID do dashboard gerenciado no Datadog"
  value       = datadog_dashboard.microsservicos.id
}

output "dashboard_url" {
  description = "URL completa do dashboard (site us5)"
  value       = "${trimsuffix(replace(var.dd_api_url, "api.", "app."), "/")}${datadog_dashboard.microsservicos.url}"
}

output "monitor_ids" {
  description = "IDs dos monitores gerenciados por tipo/serviço"
  value = merge(
    { for key, monitor in datadog_monitor.http_5xx : "http_5xx_${key}" => monitor.id },
    { for key, monitor in datadog_monitor.http_p95 : "http_p95_${key}" => monitor.id },
    { for key, monitor in datadog_monitor.jvm_heap : "jvm_heap_${key}" => monitor.id },
    { for key, monitor in datadog_monitor.pod_restarts : "pod_restarts_${key}" => monitor.id },
    { for key, monitor in datadog_monitor.dlq_messages : "dlq_${key}" => monitor.id },
    { for key, monitor in datadog_monitor.queue_age : "queue_age_${key}" => monitor.id },
  )
}

output "monitor_names" {
  description = "Nomes dos monitores gerenciados"
  value = merge(
    { for key, monitor in datadog_monitor.http_5xx : "http_5xx_${key}" => monitor.name },
    { for key, monitor in datadog_monitor.http_p95 : "http_p95_${key}" => monitor.name },
    { for key, monitor in datadog_monitor.jvm_heap : "jvm_heap_${key}" => monitor.name },
    { for key, monitor in datadog_monitor.pod_restarts : "pod_restarts_${key}" => monitor.name },
    { for key, monitor in datadog_monitor.dlq_messages : "dlq_${key}" => monitor.name },
    { for key, monitor in datadog_monitor.queue_age : "queue_age_${key}" => monitor.name },
  )
}

output "slo_ids" {
  description = "IDs dos SLOs de disponibilidade/latência"
  value = merge(
    { for key, slo in datadog_service_level_objective.availability : "availability_${key}" => slo.id },
    { for key, slo in datadog_service_level_objective.latency : "latency_${key}" => slo.id },
  )
}

output "synthetic_test_ids" {
  description = "IDs dos synthetic tests públicos"
  value = {
    health       = length(datadog_synthetics_test.health) > 0 ? datadog_synthetics_test.health[0].id : null
    auth_openapi = length(datadog_synthetics_test.auth_openapi) > 0 ? datadog_synthetics_test.auth_openapi[0].id : null
  }
}

output "edge_monitor_ids" {
  description = "IDs dos monitores de borda (5xx e latência do API Gateway)"
  value = {
    edge_5xx     = datadog_monitor.edge_5xx.id
    edge_latency = datadog_monitor.edge_latency.id
  }
}

output "cloudwatch_events_forwarding" {
  description = "Status do fallback CloudWatch -> Datadog Events"
  value = local.cloudwatch_forwarding_enabled ? {
    api_destination = aws_cloudwatch_event_api_destination.datadog[0].arn
    rule            = aws_cloudwatch_event_rule.cloudwatch_alarm[0].name
  } : null
}
