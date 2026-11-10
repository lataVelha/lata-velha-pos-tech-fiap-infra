# Barramento de eventos da saga (Épico 13).
#
# Topologia:
#   SNS lata-velha-events
#     ├── SQS lata-velha-os-service-events (+ DLQ)
#     ├── SQS lata-velha-inventory-service-events (+ DLQ)
#     └── SQS lata-velha-billing-service-events (+ DLQ)
#
# Filas standard (não FIFO): a saga é at-least-once e tolera ordem.

locals {
  consumers = {
    os        = "os-service"
    inventory = "inventory-service"
    billing   = "billing-service"
  }

  topic_name = "${var.project_name}-events"

  queue_names = {
    for key, suffix in local.consumers : key => "${var.project_name}-${suffix}-events"
  }
}

resource "aws_sns_topic" "events" {
  name = local.topic_name

  tags = {
    Name = local.topic_name
  }
}

resource "aws_sqs_queue" "dlq" {
  for_each = local.consumers

  name                      = "${local.queue_names[each.key]}-dlq"
  message_retention_seconds = var.dlq_message_retention_seconds
  sqs_managed_sse_enabled   = true

  tags = {
    Name = "${local.queue_names[each.key]}-dlq"
  }
}

resource "aws_sqs_queue" "main" {
  for_each = local.consumers

  name                       = local.queue_names[each.key]
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = {
    Name = local.queue_names[each.key]
  }
}
