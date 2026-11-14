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
