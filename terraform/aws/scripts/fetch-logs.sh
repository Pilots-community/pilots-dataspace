#!/usr/bin/env bash
set -euo pipefail

# Fetch recent CloudWatch logs for every pilots ECS service, into one file.
#
# Usage:
#   ./scripts/fetch-logs.sh [duration] [output_file]
#
# Defaults: duration=30m, output_file=services.log
# Reads log group name from `terraform output`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DURATION="${1:-30m}"
OUTPUT_FILE="${2:-services.log}"

cd "${TF_DIR}"
LOG_GROUP=$(terraform output -raw log_group_name)

SERVICES=(controlplane dataplane identityhub dashboard did-server vault db-seeder seeder)

: > "${OUTPUT_FILE}"

for svc in "${SERVICES[@]}"; do
  echo "Fetching ${svc}..."
  {
    printf '################################################################################\n'
    printf '# %s\n' "${svc}"
    printf '################################################################################\n'
    aws logs tail "${LOG_GROUP}" --log-stream-name-prefix "${svc}" --since "${DURATION}" --format short 2>&1 || true
    printf '\n'
  } >> "${OUTPUT_FILE}"
done

echo "Done — wrote ${OUTPUT_FILE}"
