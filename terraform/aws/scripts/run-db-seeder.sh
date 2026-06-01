#!/usr/bin/env bash
set -euo pipefail

# Runs the db-seeder ECS task (creates identityhub + dataplane databases).
# Idempotent — re-running is safe.
#
# Usage:
#   ./scripts/run-db-seeder.sh
#
# Reads `terraform output -raw db_seeder_run_command` and pipes to bash.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${TF_DIR}"
terraform output -raw db_seeder_run_command | bash
