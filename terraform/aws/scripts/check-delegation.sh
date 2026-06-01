#!/usr/bin/env bash
set -euo pipefail

# Checks whether NS delegation for the connector domain is live so that ACM DNS
# validation can complete. Run this BEFORE `terraform apply` — re-applying
# before delegation resolves just burns the 20-minute ACM validation timeout.
#
# Prints the Route53 nameservers to set at the parent registrar, then compares
# them against what public DNS currently returns and reports ready / not-ready.
#
# Prerequisites:
#   - aws-vault session active (`aws-vault exec pilots --no-session`)
#   - terraform apply has created the Route53 zone (a partial apply is fine)
#
# Usage:
#   ./scripts/check-delegation.sh [domain]
#
# Domain defaults to the value parsed from `terraform output dashboard_url`.
# Exit code 0 = delegation live, 1 = not ready / error.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REGION="${AWS_REGION:-eu-west-3}"

cd "${TF_DIR}"

DOMAIN="${1:-}"
if [[ -z "${DOMAIN}" ]]; then
  DOMAIN=$(terraform output -raw dashboard_url 2>/dev/null | sed -E 's#https?://##; s#/.*##' || true)
fi
if [[ -z "${DOMAIN}" ]]; then
  echo "ERROR: could not determine the domain. Pass it explicitly:" >&2
  echo "  ./scripts/check-delegation.sh pilots.example.com" >&2
  exit 1
fi

echo "Domain: ${DOMAIN}"
echo

# Expected nameservers — prefer terraform state, fall back to a Route53 query
# (the zone may exist even if a partial apply never finalised outputs).
EXPECTED=$(terraform output -json route53_nameservers 2>/dev/null \
  | python3 -c "import json,sys; print('\n'.join(sorted(s.rstrip('.').lower() for s in json.load(sys.stdin))))" 2>/dev/null || true)

if [[ -z "${EXPECTED}" ]]; then
  zone_id=$(aws route53 list-hosted-zones-by-name \
    --dns-name "${DOMAIN}" --max-items 1 \
    --query "HostedZones[?Name=='${DOMAIN}.'].Id | [0]" \
    --output text --region "${REGION}" 2>/dev/null || true)
  if [[ -n "${zone_id}" && "${zone_id}" != "None" ]]; then
    EXPECTED=$(aws route53 get-hosted-zone --id "${zone_id}" \
      --query 'DelegationSet.NameServers' --output text 2>/dev/null \
      | tr '\t' '\n' | sed -E 's/\.$//' | tr 'A-Z' 'a-z' | sort || true)
  fi
fi

if [[ -z "${EXPECTED}" ]]; then
  echo "ERROR: could not read the Route53 nameservers (no terraform output and" >&2
  echo "no matching hosted zone). Has terraform apply created the zone yet?" >&2
  exit 1
fi

echo "=== Set these NS records at the parent DNS (for '${DOMAIN}') ==="
echo "${EXPECTED}" | sed 's/^/  /'
echo

# What public DNS currently returns.
ACTUAL=$(dig +short NS "${DOMAIN}" 2>/dev/null | sed -E 's/\.$//' | tr 'A-Z' 'a-z' | sort | grep . || true)

echo "=== Currently resolving via public DNS ==="
if [[ -z "${ACTUAL}" ]]; then
  echo "  (none — delegation not visible yet)"
else
  echo "${ACTUAL}" | sed 's/^/  /'
fi
echo

# Delegation is live when every expected nameserver is present in the answer.
missing=0
while IFS= read -r ns; do
  [[ -z "${ns}" ]] && continue
  grep -qxF "${ns}" <<< "${ACTUAL}" || missing=$((missing + 1))
done <<< "${EXPECTED}"

if [[ "${missing}" -eq 0 && -n "${ACTUAL}" ]]; then
  echo "OK: delegation is live. Safe to run terraform apply."
  exit 0
else
  echo "NOT READY: ${missing} expected nameserver(s) not yet visible. Wait for"
  echo "DNS propagation and re-run this script before applying."
  exit 1
fi
