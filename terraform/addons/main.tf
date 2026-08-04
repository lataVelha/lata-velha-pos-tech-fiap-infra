# Le os outputs do bootstrap para obter vpc_id, subnets e dados do node group.
data "terraform_remote_state" "bootstrap" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "lata-velha/bootstrap/terraform.tfstate"
    region = var.region
  }
}

locals {
  bootstrap = data.terraform_remote_state.bootstrap.outputs
}

module "alb" {
  source = "../modules/alb"

  name                   = var.project_name
  vpc_id                 = local.bootstrap.vpc_id
  public_subnet_ids      = local.bootstrap.public_subnet_ids
  node_security_group_id = local.bootstrap.cluster_security_group_id
  node_asg_name          = local.bootstrap.node_asg_name
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
