variable "region" {
  description = "Regiao da AWS"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefixo dos recursos"
  type        = string
  default     = "lata-velha"
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "state_bucket" {
  description = "Bucket S3 que armazena o estado do bootstrap"
  type        = string
}

# Conexao com o EKS — lidos dos outputs do bootstrap e passados via TF_VAR_
# porque provider config nao aceita data sources.
variable "cluster_endpoint" {
  description = "Endpoint do EKS cluster"
  type        = string
}

variable "cluster_ca_data" {
  description = "CA certificate do EKS cluster (base64)"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Nome do EKS cluster"
  type        = string
}

# Credenciais AWS para o Cluster Autoscaler no AWS Academy.
# O AWS Academy nao permite IRSA — injetadas via kubernetes_secret.
# Passadas via TF_VAR_ no apply.sh e no GitHub Actions — nunca no tfvars.
variable "aws_access_key_id" {
  description = "AWS Access Key ID (Cluster Autoscaler — AWS Academy)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "aws_secret_access_key" {
  description = "AWS Secret Access Key (Cluster Autoscaler — AWS Academy)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "aws_session_token" {
  description = "AWS Session Token (Cluster Autoscaler — AWS Academy)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "dd_api_key" {
  description = "Datadog API key para o Agent (APM + Logs)"
  type        = string
  sensitive   = true
  default     = ""
}
