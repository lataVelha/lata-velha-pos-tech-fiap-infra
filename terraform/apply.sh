#!/usr/bin/env bash
#
# apply.sh — pipeline local e destroy da infra base:
#
#   (padrão)   [1/2] Bootstrap (VPC+EKS+ECR) → [2/2] Addons (ALB interno+API Gateway+autoscaler)
#   --destroy  [1/2] Addons → [2/2] Bootstrap
#
# Os addons (API Gateway do app) precisam do ARN da lambda authorizer, que
# só existe depois do repo lambda ser aplicado — por isso bootstrap e addons
# podem ser rodados em separado com --bootstrap-only / --addons-only. NUM
# DEPLOY DO ZERO use as flags: bootstrap-only → infra-db → lambda → addons-only
# → app. O modo padrão (sem flags, os dois juntos) só funciona se o repo
# lambda já tiver sido aplicado antes — serve para reaplicar tudo depois que
# a stack inteira já existe. O apply.sh raiz do mono repo já faz a
# intercalação certa: infra bootstrap → infra-db → lambda → infra addons → app.
#
# O RDS (repo infra-db) e o deploy da aplicação (repo app) NÃO são
# gerenciados por este script — cada um tem seu próprio apply/pipeline.
#
# Uso:
#   ./apply.sh                    — bootstrap + addons, com confirmação interativa
#   ./apply.sh --auto             — sem confirmação
#   ./apply.sh --bootstrap-only   — só o bootstrap (VPC+EKS+ECR)
#   ./apply.sh --addons-only      — só os addons (requer bootstrap já aplicado e,
#                                    para o API Gateway, o repo lambda já aplicado)
#   ./apply.sh --destroy          — destroi tudo com confirmação
#   ./apply.sh --destroy --auto   — destroi tudo sem confirmação
#
# Pré-requisitos:
#   cp addons/terraform.tfvars.example addons/terraform.tfvars   # se aplicavel
#   # As credenciais AWS do Cluster Autoscaler são lidas do ambiente (aws configure)

set -euo pipefail

AUTO=""
DESTROY=false
BOOTSTRAP_ONLY=false
ADDONS_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto)           AUTO="-auto-approve" ;;
    --destroy)        DESTROY=true ;;
    --bootstrap-only) BOOTSTRAP_ONLY=true ;;
    --addons-only)     ADDONS_ONLY=true ;;
    *)
      echo "Flag desconhecida: $1"
      echo "Uso: ./apply.sh [--auto] [--bootstrap-only|--addons-only] [--destroy]"
      exit 1
      ;;
  esac
  shift
done

if $BOOTSTRAP_ONLY && $ADDONS_ONLY; then
  echo "Use --bootstrap-only OU --addons-only, não os dois."
  exit 1
fi

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

run_addons() {
  local step_label="$1"
  echo ""
  echo "==> $step_label — ALB interno + API Gateway + autoscaler"
  tf_init "$BOOTSTRAP_DIR" > /dev/null 2>&1
  export TF_VAR_cluster_endpoint=$(terraform -chdir="$BOOTSTRAP_DIR" output -raw cluster_endpoint)
  export TF_VAR_cluster_ca_data=$(terraform -chdir="$BOOTSTRAP_DIR" output -raw cluster_certificate_authority_data)
  export TF_VAR_cluster_name=$(terraform -chdir="$BOOTSTRAP_DIR" output -raw cluster_name)
  tf_init "$ADDONS_DIR"
  if $DESTROY; then
    terraform -chdir="$ADDONS_DIR" destroy $AUTO
  else
    terraform -chdir="$ADDONS_DIR" apply $AUTO
  fi
}

run_bootstrap() {
  local step_label="$1"
  echo ""
  echo "==> $step_label — VPC + EKS + ECR"
  tf_init "$BOOTSTRAP_DIR"
  if $DESTROY; then
    terraform -chdir="$BOOTSTRAP_DIR" destroy $AUTO
  else
    terraform -chdir="$BOOTSTRAP_DIR" apply $AUTO
  fi
}

if $BOOTSTRAP_ONLY; then
  run_bootstrap "Bootstrap"
  exit 0
fi

if $ADDONS_ONLY; then
  run_addons "Addons"
  exit 0
fi

if $DESTROY; then
  run_addons "[1/2] Destruindo addons"
  run_bootstrap "[2/2] Destruindo bootstrap"
  exit 0
fi

run_bootstrap "[1/2] Bootstrap"
run_addons "[2/2] Addons"

echo ""
echo "==> Infra base concluída."
