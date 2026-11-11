# Subscriptions SNS → SQS com raw delivery e filter policy por eventType
# (Story 13.2). Cada fila recebe apenas os eventos que o serviço sabe
# processar; o body entregue é o JSON do EventEnvelope, sem o wrapper do SNS.

locals {
  filter_policies = {
    os = [
      "PaymentDone",
      "CobrancaEmitida",
      "OrcamentoAprovado",
      "OrcamentoReprovado",
      "InventoryChecked",
      "PecaCompletamenteAlocada",
      "DeducaoEstoqueFalhou",
    ]
    inventory = [
      "OrcamentoAprovado",
      "ServiceEnded",
    ]
    billing = [
      "DiagnosticoFinalizado",
      "OSEnded",
    ]
  }
}

resource "aws_sns_topic_subscription" "sqs" {
  for_each = local.consumers

  topic_arn            = aws_sns_topic.events.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.main[each.key].arn
  raw_message_delivery = true
  filter_policy_scope  = "MessageAttributes"
  filter_policy = jsonencode({
    eventType = local.filter_policies[each.key]
  })
}

# Só o tópico deste stack pode publicar nas filas.
data "aws_iam_policy_document" "queue" {
  for_each = local.consumers

  statement {
    sid    = "AllowSnsPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.main[each.key].arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.events.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "main" {
  for_each = local.consumers

  queue_url = aws_sqs_queue.main[each.key].id
  policy    = data.aws_iam_policy_document.queue[each.key].json
}
