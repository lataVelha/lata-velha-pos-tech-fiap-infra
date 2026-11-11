#!/usr/bin/env bash
#
# apply.sh — provisiona (ou destroi) a borda da API no API Gateway
# compartilhado: integracao com o ALB + rotas publicas + catch-all protegido.
#
# Uso:
#   ./apply.sh                  — apply com confirmacao interativa
#   ./apply.sh --auto           — apply sem confirmacao
#   ./apply.sh --destroy        — destroy com confirmacao
#   ./apply.sh --destroy --auto — destroy sem confirmacao
#
# Pre-requisitos:
#   - addons aplicado (API Gateway + ALB + VPC Link + listener)
#   - lambda aplicado (jwt_authorizer_id)
#   - credenciais AWS no ambiente (AWS Academy ou role real)

set -Eeuo pipefail

if [[ -t 1 ]]; then
  C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;31m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_DIM=''; C_RESET=''
fi

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
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "${C_BLUE}════════════════════════════════════════════════════════════${C_RESET}"
if $DESTROY; then
  echo "${C_YELLOW}  EDGE — Destruindo integracao + rotas do API Gateway${C_RESET}"
else
  echo "  EDGE — Integracao com o ALB + rotas publicas/protegidas"
fi
echo "${C_BLUE}════════════════════════════════════════════════════════════${C_RESET}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="lata-velha-tfstate-${ACCOUNT_ID}"

if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "${C_DIM}Bucket $BUCKET nao existe — rode o bootstrap primeiro.${C_RESET}"
  exit 1
fi

export TF_VAR_region="$REGION"
export TF_VAR_state_bucket="$BUCKET"

terraform -chdir="$SCRIPT_DIR" init -reconfigure \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="region=${REGION}"

if $DESTROY; then
  terraform -chdir="$SCRIPT_DIR" destroy $AUTO
  echo "${C_GREEN}✓ Borda destruida.${C_RESET}"
  exit 0
fi

terraform -chdir="$SCRIPT_DIR" apply $AUTO

echo ""
echo "${C_GREEN}✓ Borda provisionada.${C_RESET}"
terraform -chdir="$SCRIPT_DIR" output
