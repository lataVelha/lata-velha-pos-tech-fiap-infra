# IAM do barramento (Story 13.3).
#
# AWS Academy: o node usa o LabRole, então `enable_irsa = false` (default) e
# nenhuma role é criada. Em AWS real, `enable_irsa = true` cria uma role por
# serviço confiando no OIDC provider do EKS, com permissão mínima:
#   - sns:Publish no tópico
#   - sqs:ReceiveMessage, DeleteMessage, GetQueueAttributes,
#     ChangeMessageVisibility na própria fila
#
# A anotação do ServiceAccount correspondente está documentada no README do
# módulo (kubectl annotate ... eks.amazonaws.com/role-arn=<output>).

data "aws_eks_cluster" "this" {
  count = var.enable_irsa ? 1 : 0
  name  = var.cluster_name
}

locals {
  oidc_issuer = var.enable_irsa ? replace(data.aws_eks_cluster.this[0].identity[0].oidc[0].issuer, "https://", "") : ""
  irsa_roles  = var.enable_irsa ? local.consumers : {}
}

data "aws_iam_policy_document" "irsa_assume" {
  for_each = local.irsa_roles

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_eks_cluster.this[0].identity[0].oidc[0].issuer]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${var.project_name}-${each.value}:${var.project_name}-${each.value}"]
    }
  }
}

data "aws_iam_policy_document" "messaging" {
  for_each = local.consumers

  statement {
    sid       = "PublishDomainEvents"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.events.arn]
  }

  statement {
    sid    = "ConsumeOwnQueue"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [aws_sqs_queue.main[each.key].arn]
  }
}

resource "aws_iam_role" "service" {
  for_each = local.irsa_roles

  name               = "${var.project_name}-${each.value}-messaging"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume[each.key].json

  tags = {
    Service = each.value
  }
}

resource "aws_iam_policy" "service" {
  for_each = local.irsa_roles

  name   = "${var.project_name}-${each.value}-messaging"
  policy = data.aws_iam_policy_document.messaging[each.key].json
}

resource "aws_iam_role_policy_attachment" "service" {
  for_each = local.irsa_roles

  role       = aws_iam_role.service[each.key].name
  policy_arn = aws_iam_policy.service[each.key].arn
}
