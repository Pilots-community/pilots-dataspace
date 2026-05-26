#!/usr/bin/env bash
set -euo pipefail

# Force-deletes Terraform-managed Secrets Manager secrets that are stuck in the
# "scheduled for deletion" state after a `terraform destroy`. AWS refuses to
# recreate a secret while an old one with the same name is pending deletion, so
# a destroy->apply cycle fails on CreateSecret until these are purged.
#
# SAFE BY DESIGN: only purges secrets that are actually scheduled for deletion
# (DeletedDate set). Active secrets and the operator-uploaded key PEMs are left
# untouched, so running this against a live deployment is a no-op.
#
# Prerequisites:
#   - aws-vault session active (`aws-vault exec pilots --no-session`)
#
# Usage:
#   ./scripts/purge-secrets.sh [environment]
#
# Defaults to environment=dev.

ENVIRONMENT="${1:-dev}"
REGION="${AWS_REGION:-eu-west-3}"
NAME_PREFIX="pilots-${ENVIRONMENT}"

# Terraform-managed secrets only (NOT the operator-uploaded key PEMs from
# upload-keys.sh — those are never destroyed by terraform).
SECRETS=(
  "${NAME_PREFIX}-controlplane-config"
  "${NAME_PREFIX}-dataplane-config"
  "${NAME_PREFIX}-identityhub-config"
  "${NAME_PREFIX}-did-server-nginx-conf"
  "${NAME_PREFIX}-db-password"
  "${NAME_PREFIX}-rds-credentials"
  "${NAME_PREFIX}-vault-root-token"
)

purged=0
skipped=0

for name in "${SECRETS[@]}"; do
  deleted_date=$(aws secretsmanager describe-secret \
    --region "${REGION}" --secret-id "${name}" \
    --query DeletedDate --output text 2>/dev/null || echo "MISSING")

  if [[ "${deleted_date}" == "MISSING" ]]; then
    echo "  skip    ${name} (does not exist)"
    skipped=$((skipped + 1))
  elif [[ "${deleted_date}" == "None" || -z "${deleted_date}" ]]; then
    echo "  SKIP    ${name} (ACTIVE — not scheduled for deletion, leaving alone)"
    skipped=$((skipped + 1))
  else
    aws secretsmanager delete-secret \
      --region "${REGION}" --secret-id "${name}" \
      --force-delete-without-recovery --query ARN --output text > /dev/null
    echo "  purged  ${name} (was pending deletion since ${deleted_date})"
    purged=$((purged + 1))
  fi
done

echo
echo "Done: ${purged} purged, ${skipped} skipped. Safe to re-run terraform apply."
