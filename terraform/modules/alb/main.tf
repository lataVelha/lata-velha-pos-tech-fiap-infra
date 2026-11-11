resource "aws_security_group" "this" {
  name        = "${var.name}-alb-sg"
  description = "ALB interno: so aceita trafego do VPC Link do API Gateway - sem acesso direto da internet"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Unica origem de trafego permitida no ALB: os ENIs do VPC Link usado pelo
# API Gateway (ver modulo app-gateway). Nenhum acesso direto da internet.
resource "aws_security_group_rule" "vpc_link_to_alb" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.this.id
  source_security_group_id = var.vpc_link_security_group_id
  description              = "API Gateway VPC Link to ALB"
}

# Permite que o ALB alcance os nodes no NodePort
resource "aws_security_group_rule" "alb_to_nodes" {
  type                     = "ingress"
  from_port                = var.node_port
  to_port                  = var.node_port
  protocol                 = "tcp"
  security_group_id        = var.node_security_group_id
  source_security_group_id = aws_security_group.this.id
  description              = "ALB to EKS nodes (NodePort ${var.node_port})"
}

resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.this.id]
  subnets            = var.private_subnet_ids
}

resource "aws_lb_target_group" "this" {
  name        = "${var.name}-tg"
  port        = var.node_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"
  # Deve ser <= terminationGracePeriodSeconds (60s) para evitar TCP resets
  # após o pod encerrar mas o ALB ainda rotear para o node.
  deregistration_delay = 60

  health_check {
    path     = var.health_check_path
    port     = tostring(var.node_port) # provider exige string, não number
    protocol = "HTTP"
    interval = 30
    timeout  = 5
    # Spring Boot pode levar até 90s para subir; com interval=30 e threshold=5
    # o node tem até 150s antes de ser marcado unhealthy — cobre o startup.
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# Registra os nodes EKS no target group automaticamente via ASG.
# Quando o autoscaler adiciona/remove nodes, o ALB se atualiza sozinho.
resource "aws_autoscaling_attachment" "this" {
  autoscaling_group_name = var.node_asg_name
  lb_target_group_arn    = aws_lb_target_group.this.arn
}

# --------------------------------------------------------------------------
# Servicos migrados do app: um target group + listener rule path-based por
# servico. O app continua como default action ate o cutover (app_enabled) e
# deixa de ser destino dos paths listados aqui.
# --------------------------------------------------------------------------
resource "aws_lb_target_group" "svc" {
  for_each = var.services

  name                 = "${var.name}-${each.key}-tg"
  port                 = each.value.node_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "instance"
  deregistration_delay = 60

  health_check {
    path     = each.value.health
    port     = tostring(each.value.node_port)
    protocol = "HTTP"
    interval = 30
    timeout  = 5

    healthy_threshold   = 2
    unhealthy_threshold = 5
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_attachment" "svc" {
  for_each = var.services

  autoscaling_group_name = var.node_asg_name
  lb_target_group_arn    = aws_lb_target_group.svc[each.key].arn
}

resource "aws_lb_listener_rule" "svc" {
  for_each = var.listener_rules

  listener_arn = aws_lb_listener.http.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.svc[each.value.service].arn
  }

  condition {
    path_pattern {
      values = each.value.paths
    }
  }
}

# Libera o NodePort de cada servico no SG dos nodes, com origem no SG do ALB.
resource "aws_security_group_rule" "alb_to_nodes_svc" {
  for_each = var.services

  type                     = "ingress"
  from_port                = each.value.node_port
  to_port                  = each.value.node_port
  protocol                 = "tcp"
  security_group_id        = var.node_security_group_id
  source_security_group_id = aws_security_group.this.id
  description              = "ALB to EKS nodes (NodePort ${each.value.node_port} - ${each.key})"
}

# Cutover concluido: nenhuma regra de servico casou -> 404, em vez de cair
# no app. A default action continua no app para rollback; esta regra so e
# avaliada depois das regras de servico (priority 50000).
resource "aws_lb_listener_rule" "catch_all_404" {
  count = var.app_enabled ? 0 : 1

  listener_arn = aws_lb_listener.http.arn
  priority     = 50000

  action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      status_code  = "404"
      message_body = "not found"
    }
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}
