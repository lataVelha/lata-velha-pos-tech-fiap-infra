variable "name" {
  description = "Prefixo dos recursos ALB"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas onde o ALB (interno) sera criado"
  type        = list(string)
}

variable "vpc_link_security_group_id" {
  description = "Security group dos ENIs do VPC Link do API Gateway — unica origem de trafego liberada no ALB"
  type        = string
}

variable "node_security_group_id" {
  description = "Security group dos nodes EKS"
  type        = string
}

variable "node_asg_name" {
  description = "Nome do Auto Scaling Group dos nodes EKS"
  type        = string
}

variable "node_port" {
  description = "NodePort do servico Kubernetes"
  type        = number
  default     = 30080
}

variable "health_check_path" {
  description = "Path do health check"
  type        = string
  default     = "/actuator/health/readiness"
}

variable "app_enabled" {
  description = "Mantem o app como default action do ALB. false = catch-all 404 (cutover concluido)"
  type        = bool
  default     = true
}

variable "services" {
  description = "Target groups por servico migrado do app (NodePort + health check)"
  type = map(object({
    node_port = number
    health    = optional(string, "/actuator/health/readiness")
  }))
  default = {}
}

# A AWS limita 5 valores por condicao e 6 wildcards por listener rule. Por
# isso as regras sao declaradas separadamente dos target groups e os paths
# de um mesmo servico podem ocupar mais de uma regra (prioridades distintas).
variable "listener_rules" {
  description = "Listener rules path-based; cada item aponta para um servico do mapa services"
  type = map(object({
    service  = string
    priority = number
    paths    = list(string)
  }))
  default = {}
}
