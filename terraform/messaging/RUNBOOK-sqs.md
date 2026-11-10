# RUNBOOK — barramento SQS/SNS

Aplicável às filas:

- `lata-velha-os-service-events` (+ `-dlq`)
- `lata-velha-inventory-service-events` (+ `-dlq`)
- `lata-velha-billing-service-events` (+ `-dlq`)

## 1. Sintomas e alarmes

| Alarme | Anomalia |
|---|---|
| `<fila>-dlq-messages` | `ApproximateNumberOfMessagesVisible > 0` por 5 min |
| `<fila>-oldest-message` | `ApproximateAgeOfOldestMessage > 300s` |

## 2. Inspeção

```bash
QUEUE_URL=$(aws sqs get-queue-url --queue-name lata-velha-os-service-events-dlq --query QueueUrl --output text)
aws sqs get-queue-attributes --queue-url "$QUEUE_URL" \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible

# Espiar as mensagens (não deleta)
aws sqs receive-message --queue-url "$QUEUE_URL" --max-number-of-messages 5 \
  --visibility-timeout 0 --wait-time-seconds 0 \
  --message-attribute-names All
```

## 3. Pausar o consumidor

```bash
kubectl scale deployment/lata-velha-os -n lata-velha-os --replicas=0
```

Reverta com `--replicas=2` (ou o valor do HPA) depois de corrigir a causa.

## 4. Redrive da DLQ para a fila principal

```bash
aws sqs start-message-move-task \
  --source-arn "$(aws sqs get-queue-attributes --queue-url "$QUEUE_URL" \
      --attribute-names QueueArn --query Attributes.QueueArn --output text)" \
  --destination-arn "$(aws sqs get-queue-attributes \
      --queue-url "$(aws sqs get-queue-url --queue-name lata-velha-os-service-events --query QueueUrl --output text)" \
      --attribute-names QueueArn --query Attributes.QueueArn --output text)"
```

Acompanhe com `aws sqs list-message-move-tasks --source-arn <arn>`.

> Antes do redrive, corrija a causa (contrato, banco, permissão). A mensagem
> envenenada volta para a DLQ após 5 novas tentativas.

## 5. Reprocessar manualmente

```bash
aws sqs send-message --queue-url "$QUEUE_URL" --message-body "$(cat event.json)" \
  --message-attributes 'eventType={DataType=String,StringValue=OrcamentoAprovado}'
```

O corpo deve ser o JSON do `EventEnvelope` (o listener desserializa direto,
`RawMessageDelivery=true`).

## 6. Verificações de saúde

```bash
# fila principal e DLQ
aws sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names All

# subscriptions e filter policy
aws sns list-subscriptions-by-topic --topic-arn "$(terraform -chdir=infra/terraform/messaging output -raw sns_topic_arn)"

# logs do consumidor
kubectl logs -n lata-velha-os deploy/lata-velha-os --tail=200 | grep -i sqs
```

## 7. Escalonamento

1. Identifique o `eventId`/`eventType` nos logs (`SqsEventListener` registra ambos).
2. Se o payload estiver errado, corrija o publicador e republica.
3. Se a causa for infra (DLQ crescendo em todos os serviços), verifique o
   SNS/tópico e as permissões do LabRole/IRSA.
4. Registre o incidente e o resultado do redrive no PR/issue do serviço.
