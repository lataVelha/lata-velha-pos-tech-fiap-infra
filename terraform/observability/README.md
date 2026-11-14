# Observability (Datadog)

Stack Terraform que gerencia **dashboard + monitores** Datadog. Não cria
recursos AWS; o state fica em
`s3://lata-velha-tfstate-<account>/lata-velha/observability/terraform.tfstate`.

## Uso local

```bash
cd infra/terraform/observability
DD_API_KEY=... DD_APP_KEY=... ./apply.sh --plan   # fmt + validate + plan
DD_API_KEY=... DD_APP_KEY=... ./apply.sh --auto   # apply
DD_API_KEY=... DD_APP_KEY=... ./apply.sh --auto   # segundo apply = No changes
```

`apply.sh` exige as duas chaves (a APP key precisa de escrita em
dashboards/monitores), roda `terraform fmt -check`/`validate` e imprime
`dashboard_url` + `monitor_ids`.

## Pipeline

Workflow reutilizável: `infra/.github/workflows/observability.yml`
(`workflow_call` + `workflow_dispatch`). O mono chama em
`deploy-observability` após o addons; o destroy roda antes do destroy dos
addons. Secrets: `TF_VAR_dd_api_key`, `TF_VAR_dd_app_key` (e opcional
`TF_VAR_alert_recipients`).

## Métricas

| Serviço | Hits/errors | p95 |
|---|---|---|
| os/inventory | `trace.org.springframework.boot.server.{hits,errors}` | `p95:trace.org.springframework.boot.server` |
| billing | `trace.io.opentelemetry.spring_webmvc_6.0.server.{hits,errors}` | `p95:trace.io.opentelemetry.spring_webmvc_6.0.server` |

- Latência em **segundos**; não existe `.duration`.
- Restarts usam `kube_cluster_name`/`kube_namespace`/`kube_deployment`.
- SQS (`aws.sqs.*`) só com `aws_integration_enabled=true`; no AWS Academy o
  fallback são os alarmes CloudWatch do `infra/terraform/messaging`.

Runbook: [`../../../docs/observability-runbook.md`](../../../docs/observability-runbook.md).
