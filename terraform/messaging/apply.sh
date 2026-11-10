#!/usr/bin/env bash
#
# apply.sh — provisiona (ou destrói) o barramento SNS/SQS/DLQs do projeto.
#
# Uso:
#   ./apply.sh                  — apply com confirmação interativa
#   ./apply.sh --auto           — apply sem confirmação
#   ./apply.sh --destroy        — destroy com confirmação
#   ./apply.sh --destroy --auto — destroy sem confirmação
#
# Pré-requisitos: credenciais AWS no ambiente (AWS Academy ou role real).
# Não depende de EKS/addons.

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
  echo "${C_YELLOW}  INFRA MESSAGING — Destruindo tópico, filas, DLQs e alarmes${C_RESET}"
else
  echo "  INFRA MESSAGING — SNS + SQS + DLQs + subscriptions + alarmes"
fi
echo "${C_BLUE}════════════════════════════════════════════════════════════${C_RESET}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="lata-velha-tfstate-${ACCOUNT_ID}"

if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "${C_DIM}Bucket $BUCKET não existe — criando com versionamento...${C_RESET}"
  aws s3 mb "s3://$BUCKET" --region "$REGION"
  aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
fi

export TF_VAR_region="$REGION"

terraform -chdir="$SCRIPT_DIR" init -reconfigure \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="region=${REGION}"

if $DESTROY; then
  terraform -chdir="$SCRIPT_DIR" destroy $AUTO
  echo "${C_GREEN}✓ Barramento destruído.${C_RESET}"
  exit 0
fi

terraform -chdir="$SCRIPT_DIR" apply $AUTO

echo ""
echo "${C_GREEN}✓ Barramento provisionado.${C_RESET}"
terraform -chdir="$SCRIPT_DIR" output
