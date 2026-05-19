#!/usr/bin/env bash
set -euo pipefail

# Uploads the three operator-held PEM keys into Secrets Manager and prints the
# ARNs to paste into environments/dev.tfvars.
#
# Prerequisites:
#   - Repo-root ./generate-keys.sh has been run (creates the PEMs)
#   - aws-vault session active (`aws-vault exec pilots --no-session`)
#
# Usage:
#   ./scripts/upload-keys.sh [environment]
#
# Defaults to environment=dev. Idempotent: re-runs put a new version on each
# secret rather than failing.

ENVIRONMENT="${1:-dev}"
REGION="${AWS_REGION:-eu-west-3}"
NAME_PREFIX="pilots-${ENVIRONMENT}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# (key file path, secret name, description)
KEYS=(
  "${REPO_ROOT}/deployment/assets/issuer_private.pem|${NAME_PREFIX}-issuer-private-key|Issuer PEM private key — used by the seeder task to render did.json."
  "${REPO_ROOT}/config/certs/private-key.pem|${NAME_PREFIX}-dataplane-private-key|Dataplane EDR-signing private key (PEM)."
  "${REPO_ROOT}/config/certs/public-key.pem|${NAME_PREFIX}-dataplane-public-key|Dataplane EDR-signing public key (PEM)."
)

upload_one() {
  local path="$1" name="$2" desc="$3"

  if [[ ! -f "${path}" ]]; then
    echo "ERROR: missing ${path}. Run ./generate-keys.sh from the repo root first." >&2
    return 1
  fi

  local existing_arn
  existing_arn=$(aws secretsmanager describe-secret \
    --region "${REGION}" --secret-id "${name}" \
    --query ARN --output text 2>/dev/null || true)

  if [[ -n "${existing_arn}" && "${existing_arn}" != "None" ]]; then
    aws secretsmanager put-secret-value \
      --region "${REGION}" --secret-id "${name}" \
      --secret-string "file://${path}" \
      --output text --query VersionId > /dev/null
    echo "${name} = \"${existing_arn}\""
  else
    local arn
    arn=$(aws secretsmanager create-secret \
      --region "${REGION}" --name "${name}" --description "${desc}" \
      --secret-string "file://${path}" \
      --query ARN --output text)
    echo "${name} = \"${arn}\""
  fi
}

echo "# Copy these ARNs into environments/${ENVIRONMENT}.tfvars:"
for entry in "${KEYS[@]}"; do
  IFS='|' read -r path name desc <<< "${entry}"
  upload_one "${path}" "${name}" "${desc}"
done
