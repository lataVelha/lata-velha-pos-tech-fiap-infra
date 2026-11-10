# Alarmes operacionais do barramento (Story 15.4).
#
# - DLQ com mensagem visível por 5 min → alarme (algo falhou 5x)
# - fila principal com mensagem mais antiga que 300s → alarme (consumidor
#   atrasado ou parado)

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"

  tags = {
    Name = "${var.project_name}-alerts"
  }
}

resource "aws_sns_topic_subscription" "alerts_email" {
  count = var.alarm_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "dlq_visible" {
  for_each = local.consumers

  alarm_name          = "${local.queue_names[each.key]}-dlq-messages"
  alarm_description   = "Mensagem na DLQ de ${each.value} — ver RUNBOOK-sqs.md (inspeção e redrive)"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq[each.key].name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Service = each.value
    Runbook = "infra/terraform/messaging/RUNBOOK-sqs.md"
  }
}

resource "aws_cloudwatch_metric_alarm" "queue_age" {
  for_each = local.consumers

  alarm_name          = "${local.queue_names[each.key]}-oldest-message"
  alarm_description   = "Mensagem mais antiga da fila de ${each.value} passou de 300s — consumidor atrasado/parado"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 300
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.main[each.key].name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Service = each.value
    Runbook = "infra/terraform/messaging/RUNBOOK-sqs.md"
  }
}
