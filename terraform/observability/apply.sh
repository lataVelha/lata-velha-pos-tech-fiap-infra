#!/usr/bin/env bash
#
# apply.sh — aplica (ou destrói) monitores e dashboards Datadog.
#
# Uso:
#   DD_API_KEY=... DD_APP_KEY=... ./apply.sh [--auto] [--destroy]
#
# State próprio: lata-velha/observability/terraform.tfstate (só recursos
# Datadog; nenhum recurso AWS).

set -Eeuo pipefail

AUTO=""
DESTROY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto)    AUTO="-auto-approve" ;;
    --destroy) DESTROY=true ;;
    *)
      echo "Uso: ./apply.sh [--auto] [--destroy]" >&2
      exit 1
      ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="lata-velha-tfstate-${ACCOUNT_ID}"

export TF_VAR_dd_api_key="${DD_API_KEY:?defina DD_API_KEY}"
export TF_VAR_dd_app_key="${DD_APP_KEY:?defina DD_APP_KEY}"

terraform -chdir="$SCRIPT_DIR" init -reconfigure \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="region=${REGION}"

if $DESTROY; then
  terraform -chdir="$SCRIPT_DIR" destroy $AUTO
  echo "✓ Observability destruída."
else
  terraform -chdir="$SCRIPT_DIR" apply $AUTO
  echo "✓ Monitores e dashboards aplicados."
fi
