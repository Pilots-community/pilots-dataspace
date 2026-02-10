#!/bin/bash
set -euo pipefail

# End-to-end test for the Pilots Dataspace.
# Runs the full flow: create asset, create policy, create contract definition,
# request catalog, negotiate contract, initiate transfer, fetch data via EDR.
#
# Prerequisites: All services must be running and seeded (./start.sh or ./setup.sh).
#
# Usage:
#   ./test-e2e.sh

# ── Configuration ────────────────────────────────────────────────────────────

PROVIDER_MGMT="http://localhost:19193/management"
CONSUMER_MGMT="http://localhost:29193/management"
DATA_PLANE_PUBLIC="http://localhost:38185/public"
API_KEY="password"

# Docker Compose env vars (container-to-container addresses)
PROVIDER_DSP="http://provider-controlplane:19194/protocol"
PROVIDER_DID="did:web:provider-identityhub%3A7093"

POLL_INTERVAL=2
POLL_TIMEOUT=30

PASSED=0
FAILED=0
FAILURES=()

# ── Helpers ──────────────────────────────────────────────────────────────────

assert() {
  local description="$1"
  local condition="$2"

  if eval "$condition"; then
    echo "  PASS: $description"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $description"
    FAILED=$((FAILED + 1))
    FAILURES+=("$description")
  fi
}

poll_state() {
  local url="$1"
  local target_state="$2"
  local timeout="$3"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout" ]; do
    STATE=$(curl -s "$url" -H "X-Api-Key: $API_KEY" | jq -r '.state // empty')
    if [ "$STATE" = "$target_state" ]; then
      return 0
    fi
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
  done

  echo "    Timed out after ${timeout}s waiting for state '$target_state' (last state: '$STATE')"
  return 1
}

# ── Step 1: Create Asset ────────────────────────────────────────────────────

echo "=== Step 1: Create Asset ==="

ASSET_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${PROVIDER_MGMT}/v3/assets" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $API_KEY" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@id": "sample-asset-1",
    "properties": {
      "name": "Sample Data Asset",
      "description": "A sample dataset for testing the dataspace",
      "contenttype": "application/json"
    },
    "dataAddress": {
      "type": "HttpData",
      "baseUrl": "https://jsonplaceholder.typicode.com/todos/1"
    }
  }')

echo "  HTTP $ASSET_HTTP"
assert "Create asset returns 200 or 409" '[ "$ASSET_HTTP" = "200" ] || [ "$ASSET_HTTP" = "409" ]'

# ── Step 2: Create Policy ───────────────────────────────────────────────────

echo ""
echo "=== Step 2: Create Policy ==="

POLICY_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${PROVIDER_MGMT}/v3/policydefinitions" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $API_KEY" \
  -d '{
    "@context": {
      "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
      "odrl": "http://www.w3.org/ns/odrl/2/"
    },
    "@id": "open-policy",
    "policy": {
      "@context": "http://www.w3.org/ns/odrl.jsonld",
      "@type": "Set",
      "permission": [],
      "prohibition": [],
      "obligation": []
    }
  }')

echo "  HTTP $POLICY_HTTP"
assert "Create policy returns 200 or 409" '[ "$POLICY_HTTP" = "200" ] || [ "$POLICY_HTTP" = "409" ]'

# ── Step 3: Create Contract Definition ──────────────────────────────────────

echo ""
echo "=== Step 3: Create Contract Definition ==="

CONTRACTDEF_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${PROVIDER_MGMT}/v3/contractdefinitions" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $API_KEY" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@id": "sample-contract-def",
    "accessPolicyId": "open-policy",
    "contractPolicyId": "open-policy",
    "assetsSelector": []
  }')

echo "  HTTP $CONTRACTDEF_HTTP"
assert "Create contract definition returns 200 or 409" '[ "$CONTRACTDEF_HTTP" = "200" ] || [ "$CONTRACTDEF_HTTP" = "409" ]'

# ── Step 4: Request Catalog ─────────────────────────────────────────────────

echo ""
echo "=== Step 4: Request Catalog ==="

CATALOG_RESPONSE=$(curl -s -X POST "${CONSUMER_MGMT}/v3/catalog/request" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $API_KEY" \
  -d "{
    \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
    \"counterPartyAddress\": \"${PROVIDER_DSP}\",
    \"counterPartyId\": \"${PROVIDER_DID}\",
    \"protocol\": \"dataspace-protocol-http\"
  }")

OFFER_ID=$(echo "$CATALOG_RESPONSE" | jq -r '.["dcat:dataset"]["odrl:hasPolicy"]["@id"] // empty')
echo "  Offer ID: ${OFFER_ID:-<empty>}"
assert "Catalog returns a non-empty offer ID" '[ -n "$OFFER_ID" ]'

# ── Step 5: Negotiate Contract ──────────────────────────────────────────────

echo ""
echo "=== Step 5: Negotiate Contract ==="

NEGOTIATION_ID=$(curl -s -X POST "${CONSUMER_MGMT}/v3/contractnegotiations" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $API_KEY" \
  -d "{
    \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
    \"counterPartyAddress\": \"${PROVIDER_DSP}\",
    \"counterPartyId\": \"${PROVIDER_DID}\",
    \"protocol\": \"dataspace-protocol-http\",
    \"policy\": {
      \"@context\": \"http://www.w3.org/ns/odrl.jsonld\",
      \"@id\": \"${OFFER_ID}\",
      \"@type\": \"Offer\",
      \"assigner\": \"${PROVIDER_DID}\",
      \"target\": \"sample-asset-1\",
      \"permission\": [],
      \"prohibition\": [],
      \"obligation\": []
    }
  }" | jq -r '.["@id"]')

echo "  Negotiation ID: ${NEGOTIATION_ID}"
echo "  Polling for FINALIZED state..."

if poll_state "${CONSUMER_MGMT}/v3/contractnegotiations/${NEGOTIATION_ID}" "FINALIZED" "$POLL_TIMEOUT"; then
  AGREEMENT_ID=$(curl -s "${CONSUMER_MGMT}/v3/contractnegotiations/${NEGOTIATION_ID}" \
    -H "X-Api-Key: $API_KEY" | jq -r '.contractAgreementId // empty')
  echo "  Agreement ID: ${AGREEMENT_ID:-<empty>}"
  assert "Negotiation reaches FINALIZED with non-empty agreement ID" '[ -n "$AGREEMENT_ID" ]'
else
  AGREEMENT_ID=""
  assert "Negotiation reaches FINALIZED within ${POLL_TIMEOUT}s" 'false'
fi

# ── Step 6: Initiate Transfer ───────────────────────────────────────────────

echo ""
echo "=== Step 6: Initiate Transfer ==="

if [ -z "$AGREEMENT_ID" ]; then
  echo "  Skipped (no agreement ID from step 5)"
  FAILED=$((FAILED + 1))
  FAILURES+=("Transfer skipped — no agreement ID")
else
  TRANSFER_ID=$(curl -s -X POST "${CONSUMER_MGMT}/v3/transferprocesses" \
    -H "Content-Type: application/json" \
    -H "X-Api-Key: $API_KEY" \
    -d "{
      \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
      \"counterPartyAddress\": \"${PROVIDER_DSP}\",
      \"counterPartyId\": \"${PROVIDER_DID}\",
      \"protocol\": \"dataspace-protocol-http\",
      \"contractId\": \"${AGREEMENT_ID}\",
      \"assetId\": \"sample-asset-1\",
      \"transferType\": \"HttpData-PULL\"
    }" | jq -r '.["@id"]')

  echo "  Transfer ID: ${TRANSFER_ID}"
  echo "  Polling for STARTED state..."

  if poll_state "${CONSUMER_MGMT}/v3/transferprocesses/${TRANSFER_ID}" "STARTED" "$POLL_TIMEOUT"; then
    assert "Transfer reaches STARTED" 'true'
  else
    assert "Transfer reaches STARTED within ${POLL_TIMEOUT}s" 'false'
  fi
fi

# ── Step 7: Fetch Data via EDR ──────────────────────────────────────────────

echo ""
echo "=== Step 7: Fetch Data via EDR ==="

if [ -z "${TRANSFER_ID:-}" ]; then
  echo "  Skipped (no transfer ID from step 6)"
  FAILED=$((FAILED + 1))
  FAILURES+=("EDR fetch skipped — no transfer ID")
else
  TOKEN=$(curl -s "${CONSUMER_MGMT}/v3/edrs/${TRANSFER_ID}/dataaddress" \
    -H "X-Api-Key: $API_KEY" | jq -r '.authorization // empty')

  if [ -z "$TOKEN" ]; then
    echo "  Failed to retrieve EDR token"
    assert "EDR token is non-empty" 'false'
  else
    DATA_HTTP=$(curl -s -o /tmp/e2e-data-response.json -w "%{http_code}" "$DATA_PLANE_PUBLIC" \
      -H "Authorization: Bearer $TOKEN")
    echo "  HTTP $DATA_HTTP"

    DATA_VALID_JSON=false
    if jq . /tmp/e2e-data-response.json > /dev/null 2>&1; then
      DATA_VALID_JSON=true
    fi

    assert "Data plane returns HTTP 200" '[ "$DATA_HTTP" = "200" ]'
    assert "Data plane response is valid JSON" '[ "$DATA_VALID_JSON" = "true" ]'
  fi
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo "  Results: ${PASSED} passed, ${FAILED} failed"
echo "========================================"

if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "Failures:"
  for f in "${FAILURES[@]}"; do
    echo "  - $f"
  done
  exit 1
fi

exit 0
