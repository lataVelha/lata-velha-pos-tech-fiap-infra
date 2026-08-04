#!/usr/bin/env bash
#
# apply.sh — pipeline local e destroy da infra base:
#
#   (padrão)   [1/2] Bootstrap (VPC+EKS+ECR) → [2/2] Addons (ALB+autoscaler)
#   --destroy  [1/2] Addons → [2/2] Bootstrap
#
# O RDS (repo infra-db) e o deploy da aplicação (repo app) NÃO são
# gerenciados por este script — cada um tem seu próprio apply/pipeline.
# Ordem entre repos: infra bootstrap → infra addons → infra-db → app deploy.
#
# Uso:
#   ./apply.sh              — pipeline com confirmação interativa
#   ./apply.sh --auto       — pipeline sem confirmação
#   ./apply.sh --destroy    — destroi tudo com confirmação
#   ./apply.sh --destroy --auto — destroi tudo sem confirmação
#
# Pré-requisitos:
#   cp addons/terraform.tfvars.example addons/terraform.tfvars   # se aplicavel
#   # As credenciais AWS do Cluster Autoscaler são lidas do ambiente (aws configure)

set -euo pipefail

AUTO=""
DESTROY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto)    AUTO="-auto-approve" ;;
    --destroy) DESTROY=true ;;
    *)
      echo "Flag desconhecida: $1"
      echo "Uso: ./apply.sh [--auto] [--destroy]"
      exit 1
      ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$SCRIPT_DIR/bootstrap"
ADDONS_DIR="$SCRIPT_DIR/addons"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="lata-velha-tfstate-${ACCOUNT_ID}"

echo "==> Bucket de estado: $BUCKET"
if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "    Criando bucket..."
  aws s3 mb "s3://$BUCKET" --region "$REGION"
  aws s3api put-bucket-versioning \
    --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled
  echo "    Bucket criado com versionamento ativado."
fi

tf_init() {
  local dir="$1"
  terraform -chdir="$dir" init -reconfigure \
    -backend-config="bucket=${BUCKET}" \
    -backend-config="region=${REGION}"
}

# Credenciais AWS para o Cluster Autoscaler (AWS Academy não permite IRSA).
export TF_VAR_aws_access_key_id="${AWS_ACCESS_KEY_ID:-$(aws configure get aws_access_key_id 2>/dev/null || echo '')}"
export TF_VAR_aws_secret_access_key="${AWS_SECRET_ACCESS_KEY:-$(aws configure get aws_secret_access_key 2>/dev/null || echo '')}"
export TF_VAR_aws_session_token="${AWS_SESSION_TOKEN:-$(aws configure get aws_session_token 2>/dev/null || echo '')}"
export TF_VAR_state_bucket="$BUCKET"

if $DESTROY; then
  echo ""
  echo "==> [1/2] Destruindo addons (ALB + autoscaler + metrics-server)..."
  tf_init "$BOOTSTRAP_DIR" > /dev/null 2>&1
  export TF_VAR_cluster_endpoint=$(terraform -chdir="$BOOTSTRAP_DIR" output -raw cluster_endpoint 2>/dev/null || echo "")
  export TF_VAR_cluster_ca_data=$(terraform -chdir="$BOOTSTRAP_DIR" output -raw cluster_certificate_authority_data 2>/dev/null || echo "")
  export TF_VAR_cluster_name=$(terraform -chdir="$BOOTSTRAP_DIR" output -raw cluster_name 2>/dev/null || echo "")
  tf_init "$ADDONS_DIR"
  terraform -chdir="$ADDONS_DIR" destroy $AUTO

  echo ""
  echo "==> [2/2] Destruindo bootstrap (VPC + EKS + ECR)..."
  tf_init "$BOOTSTRAP_DIR"
  terraform -chdir="$BOOTSTRAP_DIR" destroy $AUTO

  exit 0
fi

echo ""
echo "==> [1/2] Bootstrap — VPC + EKS + ECR"
tf_init "$BOOTSTRAP_DIR"
terraform -chdir="$BOOTSTRAP_DIR" apply $AUTO

echo ""
echo "==> [2/2] Addons — ALB + autoscaler + metrics-server"
export TF_VAR_cluster_endpoint=$(terraform -chdir="$BOOTSTRAP_DIR" output -raw cluster_endpoint)
export TF_VAR_cluster_ca_data=$(terraform -chdir="$BOOTSTRAP_DIR" output -raw cluster_certificate_authority_data)
export TF_VAR_cluster_name=$(terraform -chdir="$BOOTSTRAP_DIR" output -raw cluster_name)
tf_init "$ADDONS_DIR"
terraform -chdir="$ADDONS_DIR" apply $AUTO

echo ""
echo "==> Infra base concluída."
echo "    Próximo passo: aplicar o infra-db e depois o deploy do app."
