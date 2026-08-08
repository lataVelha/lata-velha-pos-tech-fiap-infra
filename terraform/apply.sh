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
#   aws configure   # credenciais AWS (tambem usadas pelo Cluster Autoscaler)
#   # Nao precisa de terraform.tfvars: bootstrap/addons nao tem variavel
#   # obrigatoria sem default — tudo que varia (state_bucket, cluster_endpoint,
#   # cluster_ca_data, cluster_name, credenciais AWS) e injetado por este script.

set -Eeuo pipefail

# --------------------------- saída no terminal ------------------------------
if [[ -t 1 ]]; then
  C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'; C_RED=$'\033[1;31m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_DIM=''; C_RESET=''
fi

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
      echo "${C_RED}Flag desconhecida: $1${C_RESET}"
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

if $BOOTSTRAP_ONLY; then
  MODE_LABEL="Bootstrap (VPC + EKS + ECR)"
elif $ADDONS_ONLY; then
  MODE_LABEL="Addons (ALB interno + API Gateway + Autoscaler)"
else
  MODE_LABEL="Bootstrap + Addons (pipeline completo)"
fi

echo "${C_BLUE}════════════════════════════════════════════════════════════${C_RESET}"
if $DESTROY; then
  echo "${C_YELLOW}  INFRA — Destruindo: ${MODE_LABEL}${C_RESET}"
else
  echo "  INFRA — ${MODE_LABEL}"
fi
echo "${C_BLUE}════════════════════════════════════════════════════════════${C_RESET}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="lata-velha-tfstate-${ACCOUNT_ID}"

echo "${C_DIM}Bucket de estado: $BUCKET${C_RESET}"
if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "${C_DIM}  Bucket não existe — criando...${C_RESET}"
  aws s3 mb "s3://$BUCKET" --region "$REGION"
  aws s3api put-bucket-versioning \
    --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled
  echo "${C_GREEN}  ✓ Bucket criado com versionamento ativado.${C_RESET}"
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
  echo "${C_BLUE}==> ${step_label}${C_RESET} ${C_DIM}— ALB interno + API Gateway + autoscaler${C_RESET}"
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
  echo "${C_GREEN}✓ ${step_label} concluído.${C_RESET}"
}

run_bootstrap() {
  local step_label="$1"
  echo ""
  echo "${C_BLUE}==> ${step_label}${C_RESET} ${C_DIM}— VPC + EKS + ECR${C_RESET}"
  tf_init "$BOOTSTRAP_DIR"
  if $DESTROY; then
    terraform -chdir="$BOOTSTRAP_DIR" destroy $AUTO
  else
    terraform -chdir="$BOOTSTRAP_DIR" apply $AUTO
  fi
  echo "${C_GREEN}✓ ${step_label} concluído.${C_RESET}"
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
  echo ""
  echo "${C_GREEN}✓ Infra base destruída.${C_RESET}"
  exit 0
fi

run_bootstrap "[1/2] Bootstrap"
run_addons "[2/2] Addons"

echo ""
echo "${C_GREEN}✓ Infra base concluída.${C_RESET}"
