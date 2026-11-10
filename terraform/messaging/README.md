# infra-messaging — SNS + SQS + DLQs

Módulo autocontido que provisiona o barramento de eventos da saga. State
próprio: `lata-velha/infra-messaging/terraform.tfstate`.

## Topologia

```text
SNS lata-velha-events  (standard)
 ├── SQS lata-velha-os-service-events          (+ lata-velha-os-service-events-dlq)
 ├── SQS lata-velha-inventory-service-events   (+ ...-dlq)
 └── SQS lata-velha-billing-service-events     (+ ...-dlq)
```

| Item | Valor |
|---|---|
| VisibilityTimeout (filas principais) | 120s |
| MessageRetentionPeriod (filas principais) | 345600s (4 dias) |
| MessageRetentionPeriod (DLQs) | 1209600s (14 dias) |
| SqsManagedSseEnabled | true |
| RedrivePolicy.maxReceiveCount | 5 |
| RawMessageDelivery | true |
| FilterPolicyScope | MessageAttributes (`eventType`) |

## Filter policies

| Fila | EventTypes |
|---|---|
| os-service | `PaymentDone`, `CobrancaEmitida`, `OrcamentoAprovado`, `OrcamentoReprovado`, `InventoryChecked`, `PecaCompletamenteAlocada`, `DeducaoEstoqueFalhou` |
| inventory-service | `OrcamentoAprovado`, `ServiceEnded` |
| billing-service | `DiagnosticoFinalizado`, `OSEnded` |

## Outputs

`sns_topic_arn`, `os_queue_url`, `os_queue_arn`, `os_dlq_url`, `os_dlq_arn`,
`inventory_queue_url`, `inventory_queue_arn`, `inventory_dlq_url`,
`inventory_dlq_arn`, `billing_queue_url`, `billing_queue_arn`,
`billing_dlq_url`, `billing_dlq_arn`, `alerts_topic_arn`, `irsa_role_arns`.

Os stacks dos serviços leem esses valores via `terraform_remote_state`
(Story 13.4).

## IAM

- **AWS Academy (default)**: `enable_irsa = false`. Os pods herdam o `LabRole`
  do node (IMDS hop limit 2). Nenhuma credencial estática no repositório.
- **AWS real**: `enable_irsa = true` cria uma role por serviço com permissão
  mínima (`sns:Publish` no tópico e `sqs:ReceiveMessage`/`DeleteMessage`/
  `GetQueueAttributes`/`ChangeMessageVisibility` na própria fila). Anote o
  ServiceAccount:

```bash
kubectl annotate serviceaccount lata-velha-os \
  -n lata-velha-os \
  eks.amazonaws.com/role-arn=$(terraform output -json irsa_role_arns | jq -r '.os')
```

Repita para `inventory` e `billing`. O Deployment deve declarar
`serviceAccountName: lata-velha-<serviço>` (já configurado nos manifests).

Permissão cruzada é negada: a policy de cada serviço lista apenas a própria
fila, então consumir a fila alheia resulta em `AccessDenied`.

## Operação

Alarmes CloudWatch são criados em `alarms.tf` (DLQ visível por 5 min e
`ApproximateAgeOfOldestMessage > 300s`). Runbook:
[`RUNBOOK-sqs.md`](./RUNBOOK-sqs.md).
