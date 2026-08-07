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
