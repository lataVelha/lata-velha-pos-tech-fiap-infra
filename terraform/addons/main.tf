# Le os outputs do bootstrap para obter vpc_id, subnets e dados do node group.
data "terraform_remote_state" "bootstrap" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "lata-velha/bootstrap/terraform.tfstate"
    region = var.region
  }
}

# D2 · DBM: le o state do infra-db para obter o endpoint do RDS — o Cluster
# Agent conecta no Postgres para coleta de queries/wait states. Leitura
# aditiva: nao altera nenhum recurso do infra-db.
data "terraform_remote_state" "infra_db" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "lata-velha/infra-db/terraform.tfstate"
    region = var.region
  }
}

locals {
  bootstrap = data.terraform_remote_state.bootstrap.outputs

  # rds_endpoint vem como "host:porta" (mesma convencao usada pelo repo lambda)
  dbm_host    = split(":", data.terraform_remote_state.infra_db.outputs.rds_endpoint)[0]
  dbm_port    = tonumber(split(":", data.terraform_remote_state.infra_db.outputs.rds_endpoint)[1])
  # Mesma convencoes de identifier do repo infra-db (modules/rds)
  dbm_db_identifier = "${var.project_name}-postgres"
}

# SG dos ENIs do VPC Link do API Gateway. Criado na raiz (nao dentro de
# nenhum dos dois modulos abaixo) porque alb precisa dele como origem de
# trafego permitida, e app_gateway tambem precisa do mesmo SG — se ele
# vivesse dentro de qualquer um dos dois, teriamos uma dependencia circular
# entre eles (alb -> app_gateway -> alb).
resource "aws_security_group" "vpc_link" {
  name        = "${var.project_name}-app-vpc-link-sg"
  description = "ENIs do VPC Link do API Gateway - unica origem de trafego liberada no ALB interno"
  vpc_id      = local.bootstrap.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "alb" {
  source = "../modules/alb"

  name                       = var.project_name
  vpc_id                     = local.bootstrap.vpc_id
  private_subnet_ids         = local.bootstrap.private_subnet_ids
  node_security_group_id     = local.bootstrap.cluster_security_group_id
  node_asg_name              = local.bootstrap.node_asg_name
  vpc_link_security_group_id = aws_security_group.vpc_link.id
}

module "app_gateway" {
  source = "../modules/app-gateway"

  project_name               = var.project_name
  vpc_link_subnet_ids        = local.bootstrap.private_subnet_ids
  vpc_link_security_group_id = aws_security_group.vpc_link.id
}

# Credenciais AWS para o Cluster Autoscaler.
# AWS Academy nao permite IRSA — valores chegam via TF_VAR_ e nunca ficam no tfvars.
resource "kubectl_manifest" "aws_credentials" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "aws-credentials"
      namespace = "kube-system"
    }
    type = "Opaque"
    data = {
      AWS_ACCESS_KEY_ID     = base64encode(var.aws_access_key_id)
      AWS_SECRET_ACCESS_KEY = base64encode(var.aws_secret_access_key)
      AWS_SESSION_TOKEN     = base64encode(var.aws_session_token)
    }
  })
  sensitive_fields = ["data"]
}

module "cluster_autoscaler" {
  source = "../modules/cluster-autoscaler"

  cluster_name = var.cluster_name
  region       = var.region

  depends_on = [kubectl_manifest.aws_credentials]
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.1"

  set {
    name  = "args[0]"
    value = "--kubelet-use-node-status-port"
  }
}

resource "kubernetes_namespace" "datadog" {
  metadata {
    name = "datadog"
  }
}

resource "kubernetes_secret" "datadog_api_key" {
  metadata {
    name      = "datadog-secret"
    namespace = kubernetes_namespace.datadog.metadata[0].name
  }

  data = {
    api-key = var.dd_api_key
  }

  type = "Opaque"
}

resource "helm_release" "datadog" {
  name       = "datadog"
  repository = "https://helm.datadoghq.com"
  chart      = "datadog"
  namespace  = kubernetes_namespace.datadog.metadata[0].name
  version    = "3.60.0"

  depends_on = [kubernetes_secret.datadog_api_key]

  set {
    name  = "datadog.apiKeyExistingSecret"
    value = "datadog-secret"
  }

  set {
    name  = "datadog.site"
    value = "us5.datadoghq.com"
  }

  set {
    name  = "datadog.apm.enabled"
    value = "true"
  }

  set {
    name  = "datadog.apm.portEnabled"
    value = "true"
  }

  set {
    name  = "datadog.logs.enabled"
    value = "true"
  }

  set {
    name  = "datadog.apm.instrumentation.enabled"
    value = "true"
  }

  set {
    name  = "datadog.otlp.receiver.protocols.grpc.enabled"
    value = "true"
  }

  set {
    name  = "datadog.otlp.receiver.protocols.http.enabled"
    value = "true"
  }

  # Ingestao de LOGS via OTLP (/v1/logs). Caminho correto e otlp.logs
  # (NÃO otlp.receiver.logs — ver template _containers-common-env.yaml do
  # chart: `{{- with .Values.datadog.otlp.logs }}`). Sem isso o receiver
  # responde 404 na rota de logs — traces e metrics nao sao afetados.
  set {
    name  = "datadog.otlp.logs.enabled"
    value = "true"
  }

  # Expoe as portas OTLP (4317/4318) na rede do node via hostPort.
  # Sem isso o receiver so escuta dentro do pod do Agent — o app envia
  # para http://$(HOST_IP):4318 e a conexao e recusada (nada chega:
  # traces, metricas e logs de uma vez).
  set {
    name  = "datadog.otlp.receiver.protocols.http.useHostPort"
    value = "true"
  }

  set {
    name  = "datadog.otlp.receiver.protocols.grpc.useHostPort"
    value = "true"
  }

  # ------------------------------------------------------------------
  # D2 · Database Monitoring (DBM) — RDS PostgreSQL.
  # Configuracao pelo mecanismo CLUSTER CHECK (clusterAgent.confd com
  # cluster_check: true): roda em exatamente 1 Agent por ciclo, mesmo
  # com o Agent em DaemonSet nos nodes. O chart 3.60 NAO tem values
  # datadog.databaseMonitoring — a doc oficial de DBM/RDS no Helm usa
  # o check postgres do Cluster Agent.
  # Requer usuario datadog criado no RDS com grants (ver
  # infra-db/datadog-user.sql — passo manual 1x, runners do GH Actions
  # nao alcancam o RDS privado).
  # aws.instance_endpoint habilita metricas aprimoradas do RDS via API.
  # ------------------------------------------------------------------
  set {
    name  = "clusterAgent.confd.postgres.yaml"
    value = yamlencode({
      cluster_check = true
      init_config   = {}
      instances = [
        {
          dbm      = true
          host     = local.dbm_host
          port     = local.dbm_port
          username = var.dd_dbm_username
          password = var.dd_dbm_password
          aws = {
            instance_endpoint = "https://${local.dbm_host}"
            region            = var.region
          }
          tags = [
            "dbinstanceidentifier:${local.dbm_db_identifier}",
          ]
        },
      ]
    })
  }
}
