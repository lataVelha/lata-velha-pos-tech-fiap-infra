# Story 20.3: no AWS Academy não há integração AWS nativa no Datadog.
# Este caminho encaminha os eventos de mudança de estado dos alarmes
# CloudWatch (inclusive os alarmes de DLQ/fila do infra/terraform/messaging)
# para o Datadog Events via EventBridge API destination.
#
# O alvo usa a LabRole existente (o Academy não permite CreateRole).

locals {
  cloudwatch_forwarding_enabled = (
    !var.aws_integration_enabled &&
    var.cloudwatch_events_forwarding_enabled &&
    var.aws_account_id != ""
  )
}

resource "aws_cloudwatch_event_connection" "datadog" {
  count = local.cloudwatch_forwarding_enabled ? 1 : 0

  name               = "lata-velha-datadog-events"
  authorization_type = "API_KEY"

  auth_parameters {
    api_key {
      key   = "DD-API-KEY"
      value = var.dd_api_key
    }
  }
}

resource "aws_cloudwatch_event_api_destination" "datadog" {
  count = local.cloudwatch_forwarding_enabled ? 1 : 0

  name                             = "lata-velha-datadog-events"
  invocation_endpoint              = "https://api.us5.datadoghq.com/api/v1/events"
  http_method                      = "POST"
  invocation_rate_limit_per_second = 10
  connection_arn                   = aws_cloudwatch_event_connection.datadog[0].arn
}

resource "aws_cloudwatch_event_rule" "cloudwatch_alarm" {
  count = local.cloudwatch_forwarding_enabled ? 1 : 0

  name        = "lata-velha-cloudwatch-alarms"
  description = "Encaminha mudanças de estado dos alarmes CloudWatch ao Datadog"

  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
  })
}

resource "aws_cloudwatch_event_target" "datadog" {
  count = local.cloudwatch_forwarding_enabled ? 1 : 0

  rule     = aws_cloudwatch_event_rule.cloudwatch_alarm[0].name
  arn      = aws_cloudwatch_event_api_destination.datadog[0].arn
  role_arn = "arn:aws:iam::${var.aws_account_id}:role/LabRole"

  input_transformer {
    input_paths = {
      alarmName = "$.detail.alarmName"
      state     = "$.detail.state.value"
      reason    = "$.detail.state.reason"
    }

    # O Events API não aceita ALARM/OK como alert_type; manda error e
    # preserva o estado real no texto/tags.
    input_template = <<-JSON
      {
        "title": "CloudWatch alarm <alarmName>",
        "text": "State: <state>. Reason: <reason>",
        "alert_type": "error",
        "source_type_name": "amazon cloudwatch",
        "tags": ["source:cloudwatch", "env:${var.environment}", "alarm:<alarmName>"]
      }
    JSON
  }
}
