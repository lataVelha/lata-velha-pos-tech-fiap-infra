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

variable "aws_integration_enabled" {
  description = "Cria monitores/widgets de SQS. Requer a integração AWS no Datadog; no AWS Academy fica false e o fallback são os alarmes CloudWatch do messaging."
  type        = bool
  default     = false
}

variable "kube_cluster_name" {
  description = "Tag kube_cluster_name das métricas do Agent (usada no monitor de restarts)"
  type        = string
  default     = "lata-velha-prod"
}

variable "service_namespaces" {
  description = "Namespace Kubernetes por serviço (tag kube_namespace do Agent)"
  type        = map(string)
  default = {
    os        = "lata-velha-os"
    inventory = "lata-velha-inventory"
    billing   = "lata-velha-billing"
  }
}

variable "service_deployments" {
  description = "Deployment Kubernetes por serviço (tag kube_deployment do Agent)"
  type        = map(string)
  default = {
    os        = "lata-velha-os"
    inventory = "lata-velha-inventory"
    billing   = "lata-velha-billing"
  }
}

variable "trace_metric_prefixes" {
  description = <<-EOT
    Prefixo da trace metric do span HTTP server por serviço.
    hits  = <prefixo>.hits
    errors = <prefixo>.errors
    p95   = p95:<prefixo> (a métrica-base é a distribuição de duração, em segundos;
            NÃO existe <prefixo>.duration neste setup OTel).
  EOT
  type        = map(string)
  default = {
    os        = "trace.http.request"
    inventory = "trace.http.request"
    billing   = "trace.http.request"
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

variable "app_api_url" {
  description = "URL pública do API Gateway (output app_api_endpoint do addons) — usada nos synthetic tests"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "Região AWS do fallback CloudWatch -> Datadog Events"
  type        = string
  default     = "us-east-1"
}

variable "cloudwatch_events_forwarding_enabled" {
  description = "Quando a integração AWS está off, encaminha CloudWatch Alarm State Change para o Datadog Events via EventBridge API destination"
  type        = bool
  default     = true
}

variable "aws_account_id" {
  description = "Account ID usado para montar o ARN da LabRole do EventBridge (fallback CloudWatch). Vazio = fallback desabilitado."
  type        = string
  default     = ""
}
