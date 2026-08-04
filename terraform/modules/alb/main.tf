resource "aws_security_group" "this" {
  name        = "${var.name}-alb-sg"
  description = "ALB: HTTP da internet para os nodes EKS"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
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
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.this.id]
  subnets            = var.public_subnet_ids
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
