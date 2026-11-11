output "sns_topic_arn" {
  description = "ARN do tópico SNS de eventos de domínio"
  value       = aws_sns_topic.events.arn
}

output "sns_topic_name" {
  value = aws_sns_topic.events.name
}

output "os_queue_url" {
  value = aws_sqs_queue.main["os"].id
}

output "os_queue_arn" {
  value = aws_sqs_queue.main["os"].arn
}

output "os_dlq_url" {
  value = aws_sqs_queue.dlq["os"].id
}

output "os_dlq_arn" {
  value = aws_sqs_queue.dlq["os"].arn
}

output "inventory_queue_url" {
  value = aws_sqs_queue.main["inventory"].id
}

output "inventory_queue_arn" {
  value = aws_sqs_queue.main["inventory"].arn
}

output "inventory_dlq_url" {
  value = aws_sqs_queue.dlq["inventory"].id
}

output "inventory_dlq_arn" {
  value = aws_sqs_queue.dlq["inventory"].arn
}

output "billing_queue_url" {
  value = aws_sqs_queue.main["billing"].id
}

output "billing_queue_arn" {
  value = aws_sqs_queue.main["billing"].arn
}

output "billing_dlq_url" {
  value = aws_sqs_queue.dlq["billing"].id
}

output "billing_dlq_arn" {
  value = aws_sqs_queue.dlq["billing"].arn
}

output "alerts_topic_arn" {
  description = "Tópico de alarmes CloudWatch de DLQ/idade de fila"
  value       = aws_sns_topic.alerts.arn
}

output "irsa_role_arns" {
  description = "ARNs das roles IRSA por serviço (vazio quando enable_irsa = false)"
  value       = { for key, role in aws_iam_role.service : key => role.arn }
}
