#!/usr/bin/env bash
set -euo pipefail

# Smoke-test the deployed connector. Reads endpoints from terraform outputs.
#
# Usage:
#   ./scripts/validate.sh         # basic reachability
#   ./scripts/validate.sh --deep  # also runs a DSP self-loop catalog request

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEEP=0
[[ "${1:-}" == "--deep" ]] && DEEP=1

cd "${TF_DIR}"

URLS_JSON=$(terraform output -json service_urls)
DOMAIN=$(python3 -c "import json,sys,urllib.parse as u; print(u.urlparse(json.loads(sys.argv[1])['dashboard']).hostname)" "${URLS_JSON}")
PARTICIPANT_DID=$(terraform output -raw participant_did)
ISSUER_DID=$(terraform output -raw issuer_did)

pass=0; fail=0

check() {
  local label="$1" url="$2" expect="$3"
  local code
  code=$(curl -ksS -o /dev/null -w "%{http_code}" --max-time 10 "${url}" || echo "000")
  if [[ ",${expect}," == *",${code},"* ]] || [[ "${expect}" == "any" && "${code}" != "000" ]]; then
    printf "  OK     %-32s %s -> %s\n" "${label}" "${url}" "${code}"
    pass=$((pass+1))
  else
    printf "  FAIL   %-32s %s -> %s (expected one of: %s)\n" "${label}" "${url}" "${code}" "${expect}"
    fail=$((fail+1))
  fi
}

echo "=== DNS ==="
if host "${DOMAIN}" > /dev/null 2>&1; then
  echo "  OK     ${DOMAIN} resolves"
else
  echo "  FAIL   ${DOMAIN} does not resolve — check NS delegation"
  exit 1
fi

echo
echo "=== Reachability ==="
check "dashboard"        "https://${DOMAIN}/"                                 "200,301,302"
check "did-server"       "https://${DOMAIN}:9876/.well-known/did.json"        "200,404"
check "ih credentials"   "https://${DOMAIN}:7091/api/credentials"             "200,401,404"
check "ih did"           "https://${DOMAIN}:7093/"                            "200,404"
check "cp dsp"           "https://${DOMAIN}:19194/protocol"                   "200,404,405"
check "dp public"        "https://${DOMAIN}:38185/public"                     "200,401,404"

echo
echo "=== Operator-only ports (will FAIL if your IP isn't in mgmt_cidrs) ==="
check "ih identity"      "https://${DOMAIN}:7092/api/identity/v1alpha/participants" "200,401"
check "cp mgmt"          "https://${DOMAIN}:19193/management/v3/secrets"            "200,401"

echo
echo "=== did.json content ==="
ACTUAL_DID=$(curl -ksS --max-time 5 "https://${DOMAIN}:9876/.well-known/did.json" | jq -r '.id // empty' 2>/dev/null || true)
if [[ "${ACTUAL_DID}" == "${ISSUER_DID}" ]]; then
  echo "  OK     issuer did.json id = ${ACTUAL_DID}"
else
  echo "  WARN   did.json not yet seeded (id = '${ACTUAL_DID}', expected '${ISSUER_DID}') — run the seeder ECS task"
fi

if [[ "${DEEP}" == "1" ]]; then
  echo
  echo "=== DSP self-loop catalog request ==="
  RESP=$(curl -ksS -X POST "https://${DOMAIN}:19193/management/v3/catalog/request" \
    -H 'Content-Type: application/json' -H 'x-api-key: password' \
    -d "{\"@context\":{\"@vocab\":\"https://w3id.org/edc/v0.0.1/ns/\"},
         \"@type\":\"CatalogRequest\",
         \"counterPartyAddress\":\"https://${DOMAIN}:19194/protocol\",
         \"counterPartyId\":\"${PARTICIPANT_DID}\",
         \"protocol\":\"dataspace-protocol-http\"}" \
    --max-time 30 || echo "{}")
  if echo "${RESP}" | jq -e '."@type" // .["dspace:Catalog"]' > /dev/null 2>&1; then
    echo "  OK     received a catalog response (truncated below)"
    echo "${RESP}" | jq . | head -20
  else
    echo "  FAIL   no usable catalog response:"
    echo "${RESP}" | head -10
    fail=$((fail+1))
  fi
fi

echo
echo "=== Result: ${pass} pass / ${fail} fail ==="
exit $(( fail > 0 ? 1 : 0 ))
