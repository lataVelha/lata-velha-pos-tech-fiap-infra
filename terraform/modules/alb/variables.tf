variable "name" {
  description = "Prefixo dos recursos ALB"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "Subnets publicas onde o ALB sera criado"
  type        = list(string)
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
