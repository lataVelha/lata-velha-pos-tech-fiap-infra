variable "dd_api_key" {
  description = "Datadog API key (secret)"
  type        = string
  sensitive   = true
}

variable "dd_app_key" {
  description = "Datadog Application key (secret) — necessária para gerenciar monitores/dashboards"
  type        = string
  sensitive   = true
}

variable "dd_api_url" {
  description = "Site da Datadog (us5 para o projeto)"
  type        = string
  default     = "https://api.us5.datadoghq.com/"
}

variable "environment" {
  description = "Valor da tag env nos monitores"
  type        = string
  default     = "prod"
}

variable "team" {
  description = "Valor da tag team nos monitores"
  type        = string
  default     = "lata-velha"
}

variable "services" {
  description = "Nomes de serviço no APM"
  type        = map(string)
  default = {
    os        = "lata-velha-os-service"
    inventory = "lata-velha-inventory-service"
    billing   = "lata-velha-billing-service"
  }
}

variable "queues" {
  description = "Filas SQS monitoradas (nome exato no CloudWatch/Datadog AWS integration)"
  type        = map(string)
  default = {
    os        = "lata-velha-os-service-events"
    inventory = "lata-velha-inventory-service-events"
    billing   = "lata-velha-billing-service-events"
  }
}

variable "p95_baseline_ms" {
  description = "Baseline de latência p95 HTTP por serviço (ms)"
  type        = map(number)
  default = {
    lata-velha-os-service        = 800
    lata-velha-inventory-service = 500
    lata-velha-billing-service   = 1000
  }
}

variable "alert_recipients" {
  description = "Handles de notificação (ex.: @slack-lata-velha-alerts). Vazio = só o runbook"
  type        = list(string)
  default     = []
}

variable "runbook_url" {
  description = "URL do runbook de observabilidade"
  type        = string
  default     = "https://github.com/lataVelha/lata-velha-pos-tech-fiap-mono/blob/master/docs/observability-runbook.md"
}
