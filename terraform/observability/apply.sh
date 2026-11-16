#!/usr/bin/env bash
#
# apply.sh — aplica (ou destrói) dashboards e monitores Datadog.
#
# Uso:
#   DD_API_KEY=... DD_APP_KEY=... ./apply.sh [--auto] [--plan] [--destroy]
#
# State próprio: lata-velha/observability/terraform.tfstate (só recursos
# Datadog; nenhum recurso AWS). O bucket vem da conta autenticada.
#
# A validação (fmt/validate) roda antes de qualquer plan/apply. O script
# nunca imprime DD_API_KEY/DD_APP_KEY.

set -Eeuo pipefail

AUTO=""
DESTROY=false
PLAN_ONLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto)    AUTO="-auto-approve" ;;
    --plan)    PLAN_ONLY=true ;;
    --destroy) DESTROY=true ;;
    *)
      echo "Uso: ./apply.sh [--auto] [--plan] [--destroy]" >&2
      exit 1
      ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
TERRAFORM="${TERRAFORM:-terraform}"

if ! command -v "$TERRAFORM" >/dev/null 2>&1; then
  echo "ERRO: terraform não encontrado (defina TERRAFORM=/caminho/terraform)." >&2
  exit 1
fi

: "${DD_API_KEY:?defina DD_API_KEY}"
: "${DD_APP_KEY:?defina DD_APP_KEY}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="lata-velha-tfstate-${ACCOUNT_ID}"

export TF_VAR_dd_api_key="$DD_API_KEY"
export TF_VAR_dd_app_key="$DD_APP_KEY"

echo "==> Terraform init (state: s3://${BUCKET}/lata-velha/observability/terraform.tfstate)"
"$TERRAFORM" -chdir="$SCRIPT_DIR" init -reconfigure \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="region=${REGION}"

echo "==> Terraform fmt -check"
"$TERRAFORM" -chdir="$SCRIPT_DIR" fmt -check -recursive

echo "==> Terraform validate"
"$TERRAFORM" -chdir="$SCRIPT_DIR" validate

if $DESTROY; then
  "$TERRAFORM" -chdir="$SCRIPT_DIR" destroy $AUTO
  echo "✓ Observability destruída."
  exit 0
fi

if $PLAN_ONLY; then
  "$TERRAFORM" -chdir="$SCRIPT_DIR" plan
  echo "✓ Plan concluído (nada aplicado)."
  exit 0
fi

"$TERRAFORM" -chdir="$SCRIPT_DIR" apply $AUTO

echo "==> Recursos aplicados"
"$TERRAFORM" -chdir="$SCRIPT_DIR" output dashboard_url
"$TERRAFORM" -chdir="$SCRIPT_DIR" output monitor_ids
echo "✓ Monitores e dashboard aplicados."
