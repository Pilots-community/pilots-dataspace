#!/usr/bin/env bash
set -euo pipefail

# Collects everything needed to diagnose a broken deployment into one tarball:
#   - ECS service state + deployment events (why is desiredCount != runningCount?)
#   - Stopped task reasons (image pull failures, exit codes, OOM kills, etc.)
#   - ALB target group health (which backend ports aren't passing healthchecks?)
#   - Recent CloudWatch logs per service (last 200h by default)
#   - Secrets Manager state (any pending deletion blocking apply?)
#   - Terraform state outputs
#
# Read-only: nothing is modified. Output goes into ./diagnostics/<ts>/ and a
# .tar.gz alongside it. Share the tarball when asking for help.
#
# Prerequisites:
#   - aws-vault session active (`aws-vault exec pilots --no-session`)
#   - terraform apply has run at least once (state must exist)
#
# Usage:
#   ./scripts/gather-diagnostics.sh [duration]
#
# duration: how far back to pull logs (CloudWatch `tail --since`). Default 200h.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DURATION="${1:-200h}"
REGION="${AWS_REGION:-eu-west-3}"

cd "${TF_DIR}"

TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT="${TF_DIR}/diagnostics/${TS}"
mkdir -p "${OUT}"

echo "Writing diagnostics to ${OUT}"

# Resolve everything we need from terraform state up front so the rest of the
# script doesn't have to assume names.
CLUSTER=$(terraform output -raw ecs_cluster_name)
LOG_GROUP=$(terraform output -raw log_group_name)
DOMAIN=$(terraform output -raw dashboard_url | sed -E 's#https?://##; s#/.*##')

echo "  cluster=${CLUSTER}  log_group=${LOG_GROUP}  domain=${DOMAIN}"

terraform output -json > "${OUT}/terraform-outputs.json" 2>/dev/null || true

# ----------------------------------------------------------------------------
# ECS cluster + services + tasks
# ----------------------------------------------------------------------------
echo "=== ECS cluster ==="
aws ecs describe-clusters --region "${REGION}" --clusters "${CLUSTER}" \
  > "${OUT}/cluster.json" 2>&1 || true

SERVICE_ARNS=$(aws ecs list-services --region "${REGION}" --cluster "${CLUSTER}" \
  --query 'serviceArns[]' --output text 2>/dev/null || true)

if [[ -n "${SERVICE_ARNS}" ]]; then
  # describe-services accepts up to 10 services per call; we have 6.
  # shellcheck disable=SC2086
  aws ecs describe-services --region "${REGION}" --cluster "${CLUSTER}" \
    --services ${SERVICE_ARNS} \
    > "${OUT}/services.json" 2>&1 || true
fi

# Per-service: list+describe all tasks (running AND recently stopped).
mkdir -p "${OUT}/tasks"
for status in RUNNING STOPPED; do
  for svc_arn in ${SERVICE_ARNS}; do
    svc=$(basename "${svc_arn}")
    task_arns=$(aws ecs list-tasks --region "${REGION}" --cluster "${CLUSTER}" \
      --service-name "${svc}" --desired-status "${status}" \
      --query 'taskArns[]' --output text 2>/dev/null || true)
    if [[ -n "${task_arns}" ]]; then
      # shellcheck disable=SC2086
      aws ecs describe-tasks --region "${REGION}" --cluster "${CLUSTER}" \
        --tasks ${task_arns} \
        > "${OUT}/tasks/${svc}-${status,,}.json" 2>&1 || true
    fi
  done
done

# Distilled view: stopped-task reasons (the most useful single piece of info).
{
  echo "# Stopped task reasons (last 100 tasks per service)"
  echo
  for f in "${OUT}"/tasks/*-stopped.json; do
    [[ -f "${f}" ]] || continue
    svc=$(basename "${f}" -stopped.json)
    echo "## ${svc}"
    python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
for t in data.get('tasks', []):
    print(f\"  task={t.get('taskArn','?').split('/')[-1]}\")
    print(f\"    lastStatus={t.get('lastStatus')}  stopCode={t.get('stopCode')}\")
    print(f\"    stoppedReason={t.get('stoppedReason')}\")
    for c in t.get('containers', []):
        print(f\"    container={c.get('name')}  exitCode={c.get('exitCode')}  reason={c.get('reason')}\")
    print()
" "${f}" 2>/dev/null || cat "${f}"
    echo
  done
} > "${OUT}/stopped-task-summary.txt"

# ----------------------------------------------------------------------------
# ALB target group health
# ----------------------------------------------------------------------------
echo "=== ALB target health ==="
TG_ARNS=$(aws elbv2 describe-target-groups --region "${REGION}" \
  --query "TargetGroups[?starts_with(TargetGroupName, 'pilots-')].TargetGroupArn" \
  --output text 2>/dev/null || true)

{
  for arn in ${TG_ARNS}; do
    name=$(basename "${arn}" | cut -d'/' -f1)
    echo "## ${name}"
    aws elbv2 describe-target-health --region "${REGION}" --target-group-arn "${arn}" \
      --query 'TargetHealthDescriptions[].{id:Target.Id,port:Target.Port,state:TargetHealth.State,reason:TargetHealth.Reason,description:TargetHealth.Description}' \
      --output table 2>&1 || true
    echo
  done
} > "${OUT}/target-health.txt"

# ----------------------------------------------------------------------------
# CloudWatch logs (per service, last ${DURATION})
# ----------------------------------------------------------------------------
echo "=== CloudWatch logs (last ${DURATION}) ==="
mkdir -p "${OUT}/logs"
for svc in controlplane dataplane identityhub dashboard did-server vault seeder db-seeder; do
  aws logs tail "${LOG_GROUP}" --region "${REGION}" \
    --log-stream-name-prefix "${svc}" --since "${DURATION}" --format short \
    > "${OUT}/logs/${svc}.log" 2>&1 || true
done

# ----------------------------------------------------------------------------
# Secrets Manager — names + status only (NO values)
# ----------------------------------------------------------------------------
echo "=== Secrets Manager state ==="
aws secretsmanager list-secrets --region "${REGION}" \
  --filters "Key=name,Values=pilots-" \
  --query 'SecretList[].{Name:Name,DeletedDate:DeletedDate,LastChangedDate:LastChangedDate}' \
  --output table > "${OUT}/secrets.txt" 2>&1 || true

# ----------------------------------------------------------------------------
# Reachability probe — what does the ALB actually return right now?
# ----------------------------------------------------------------------------
echo "=== Reachability probes ==="
{
  for path in "/" "/.well-known/did.json" "/issuer/did.json" "/api/credentials" "/protocol" "/public" "/management/v3/secrets"; do
    code=$(curl -ksS -o /dev/null -w "%{http_code}" --max-time 8 "https://${DOMAIN}${path}" || echo "000")
    printf "  %-32s %s\n" "${path}" "${code}"
  done
} > "${OUT}/reachability.txt"

# ----------------------------------------------------------------------------
# Pack it up.
# ----------------------------------------------------------------------------
TARBALL="${TF_DIR}/diagnostics/${TS}.tar.gz"
tar -czf "${TARBALL}" -C "${TF_DIR}/diagnostics" "${TS}"

echo
echo "Done."
echo "  Directory: ${OUT}"
echo "  Tarball:   ${TARBALL}"
echo
echo "Quick look:"
echo "  cat ${OUT}/stopped-task-summary.txt"
echo "  cat ${OUT}/target-health.txt"
echo "  cat ${OUT}/reachability.txt"
