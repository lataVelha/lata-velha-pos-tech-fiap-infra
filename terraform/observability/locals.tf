locals {
  # Mapa único de identidade + métricas reais do OTel por serviço.
  # As chaves de var.services (os/inventory/billing) são a fonte da verdade.
  trace = {
    for key, service in var.services : key => {
      service    = service
      prefix     = var.trace_metric_prefixes[key]
      hits       = "${var.trace_metric_prefixes[key]}.hits"
      errors     = "${var.trace_metric_prefixes[key]}.errors"
      latency    = var.trace_metric_prefixes[key]
      namespace  = var.service_namespaces[key]
      deployment = var.service_deployments[key]
    }
  }

  dashboard_service_template = join(" OR ", [
    for name in values(var.services) : "service:${name}"
  ])

  # A trace metric de duração é publicada em segundos. O baseline histórico
  # está em ms; convertemos aqui para não repetir a conta em cada monitor.
  p95_baseline_seconds = {
    for service, ms in var.p95_baseline_ms : service => ms / 1000
  }

  notification = join(" ", concat(var.alert_recipients, ["${var.runbook_url}"]))
  common_tags  = ["env:${var.environment}", "team:${var.team}", "managed-by:terraform"]

  sqs_note_enabled = <<-EOT
    ## SQS
    Integração AWS habilitada. Monitores de DLQ/idade de fila estão ativos.
  EOT

  sqs_note_disabled = <<-EOT
    ## SQS — integração AWS desabilitada (AWS Academy)
    O Datadog não recebe `aws.sqs.*` neste ambiente. A cobertura de DLQ e
    fila parada fica nos alarmes CloudWatch do `infra/terraform/messaging`
    (`alarms.tf`), que notificam o tópico SNS de alertas. Para habilitar os
    widgets/monitores, aplique com `aws_integration_enabled=true` em uma
    conta com permissão para a integração AWS do Datadog.
  EOT
}
