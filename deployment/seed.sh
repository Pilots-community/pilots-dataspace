#!/bin/bash
set -euo pipefail

# Seed identity data into IdentityHubs after they start.
# Usage: ./deployment/seed.sh
#
# NOTE: For Docker Compose deployment, seeding is now automatic via the
# participant-bootstrap extension. This script is kept as a manual fallback
# for native (non-Docker) development or re-seeding scenarios.
#
# Prerequisites: IdentityHubs and connectors must be running and healthy.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPERUSER_KEY="c3VwZXItdXNlcg==.superuser-token"

P1_IH_IDENTITY="http://localhost:7092/api/identity"
P2_IH_IDENTITY="http://localhost:7082/api/identity"

P1_IH_DID_PORT=7093
P2_IH_DID_PORT=7083

P1_DID="did:web:participant-1-identityhub%3A${P1_IH_DID_PORT}"
P2_DID="did:web:participant-2-identityhub%3A${P2_IH_DID_PORT}"

# Management API endpoints (for storing STS client secrets)
P1_MGMT="http://localhost:19193/management"
P2_MGMT="http://localhost:29193/management"

P1_VC_JWT=$(jq -r '.credential' "${SCRIPT_DIR}/assets/credentials/participant-1/membership-credential.json")
P2_VC_JWT=$(jq -r '.credential' "${SCRIPT_DIR}/assets/credentials/participant-2/membership-credential.json")

# Base64-encoded participant IDs for API URL paths
P1_DID_B64=$(echo -n "${P1_DID}" | base64)
P2_DID_B64=$(echo -n "${P2_DID}" | base64)

# DSP protocol endpoints (used for DID document service entries)
P1_DSP="http://participant-1-controlplane:19194/protocol"
P2_DSP="http://participant-2-controlplane:29194/protocol"

# CredentialService endpoints (IdentityHub credentials API with base64-encoded DID)
P1_CREDENTIAL_SVC="http://participant-1-identityhub:7091/api/credentials/v1/participants/${P1_DID_B64}"
P2_CREDENTIAL_SVC="http://participant-2-identityhub:7081/api/credentials/v1/participants/${P2_DID_B64}"

echo "=== Seeding Participant-1 IdentityHub ==="

# Create participant-1 participant context
echo "Creating participant-1 participant context..."
P1_RESULT=$(curl -s -w "\n%{http_code}" -X POST "${P1_IH_IDENTITY}/v1alpha/participants" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${SUPERUSER_KEY}" \
  -d "{
    \"participantContextId\": \"${P1_DID}\",
    \"did\": \"${P1_DID}\",
    \"active\": true,
    \"key\": {
      \"keyId\": \"${P1_DID}#key-1\",
      \"privateKeyAlias\": \"${P1_DID}-alias\",
      \"keyGeneratorParams\": {
        \"algorithm\": \"EdDSA\",
        \"curve\": \"Ed25519\"
      }
    },
    \"serviceEndpoints\": [
      {
        \"type\": \"CredentialService\",
        \"serviceEndpoint\": \"${P1_CREDENTIAL_SVC}\",
        \"id\": \"participant-1-credentialservice-1\"
      },
      {
        \"type\": \"ProtocolEndpoint\",
        \"serviceEndpoint\": \"${P1_DSP}\",
        \"id\": \"participant-1-dsp\"
      }
    ],
    \"roles\": []
  }")

P1_HTTP_CODE=$(echo "$P1_RESULT" | tail -1)
P1_BODY=$(echo "$P1_RESULT" | sed '$d')
echo "  HTTP ${P1_HTTP_CODE}: ${P1_BODY}"

# Extract the participant-1 API key and STS client secret for later use
if [ "$P1_HTTP_CODE" = "200" ] || [ "$P1_HTTP_CODE" = "201" ] || [ "$P1_HTTP_CODE" = "204" ]; then
  P1_API_KEY=$(echo "$P1_BODY" | jq -r '.apiKey // empty' 2>/dev/null || echo "")
  P1_CLIENT_SECRET=$(echo "$P1_BODY" | jq -r '.clientSecret // empty' 2>/dev/null || echo "")
  if [ -n "$P1_API_KEY" ]; then
    echo "  Participant-1 API Key: ${P1_API_KEY}"
  fi
fi

echo ""
echo "=== Seeding Participant-2 IdentityHub ==="

# Create participant-2 participant context
echo "Creating participant-2 participant context..."
P2_RESULT=$(curl -s -w "\n%{http_code}" -X POST "${P2_IH_IDENTITY}/v1alpha/participants" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${SUPERUSER_KEY}" \
  -d "{
    \"participantContextId\": \"${P2_DID}\",
    \"did\": \"${P2_DID}\",
    \"active\": true,
    \"key\": {
      \"keyId\": \"${P2_DID}#key-1\",
      \"privateKeyAlias\": \"${P2_DID}-alias\",
      \"keyGeneratorParams\": {
        \"algorithm\": \"EdDSA\",
        \"curve\": \"Ed25519\"
      }
    },
    \"serviceEndpoints\": [
      {
        \"type\": \"CredentialService\",
        \"serviceEndpoint\": \"${P2_CREDENTIAL_SVC}\",
        \"id\": \"participant-2-credentialservice-1\"
      },
      {
        \"type\": \"ProtocolEndpoint\",
        \"serviceEndpoint\": \"${P2_DSP}\",
        \"id\": \"participant-2-dsp\"
      }
    ],
    \"roles\": []
  }")

P2_HTTP_CODE=$(echo "$P2_RESULT" | tail -1)
P2_BODY=$(echo "$P2_RESULT" | sed '$d')
echo "  HTTP ${P2_HTTP_CODE}: ${P2_BODY}"

if [ "$P2_HTTP_CODE" = "200" ] || [ "$P2_HTTP_CODE" = "201" ] || [ "$P2_HTTP_CODE" = "204" ]; then
  P2_API_KEY=$(echo "$P2_BODY" | jq -r '.apiKey // empty' 2>/dev/null || echo "")
  P2_CLIENT_SECRET=$(echo "$P2_BODY" | jq -r '.clientSecret // empty' 2>/dev/null || echo "")
  if [ -n "$P2_API_KEY" ]; then
    echo "  Participant-2 API Key: ${P2_API_KEY}"
  fi
fi

echo ""
echo "=== Activating Participant Contexts ==="

# Participant contexts start in CREATED state. We must activate them before
# DID publishing or STS authentication will work.
echo "Activating participant-1 participant context..."
curl -s -w " HTTP %{http_code}" -X POST "${P1_IH_IDENTITY}/v1alpha/participants/${P1_DID_B64}/state?isActive=true" \
  -H "x-api-key: ${SUPERUSER_KEY}" && echo "" || echo " FAILED"

echo "Activating participant-2 participant context..."
curl -s -w " HTTP %{http_code}" -X POST "${P2_IH_IDENTITY}/v1alpha/participants/${P2_DID_B64}/state?isActive=true" \
  -H "x-api-key: ${SUPERUSER_KEY}" && echo "" || echo " FAILED"

echo ""
echo "=== Publishing DID Documents ==="

# Publish DIDs so they're resolvable via did:web
echo "Publishing participant-1 DID..."
curl -s -w " HTTP %{http_code}" -X POST "${P1_IH_IDENTITY}/v1alpha/participants/${P1_DID_B64}/dids/publish" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${SUPERUSER_KEY}" \
  -d "{\"did\": \"${P1_DID}\"}" && echo "" || echo " FAILED"

echo "Publishing participant-2 DID..."
curl -s -w " HTTP %{http_code}" -X POST "${P2_IH_IDENTITY}/v1alpha/participants/${P2_DID_B64}/dids/publish" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${SUPERUSER_KEY}" \
  -d "{\"did\": \"${P2_DID}\"}" && echo "" || echo " FAILED"

echo ""
echo "=== Storing STS Client Secrets ==="

# The connector needs the STS client secret to authenticate with the embedded STS in IdentityHub.
# The secret was auto-generated during participant context creation and returned in the response.
# We store it in the connector vault so the connector can use it for STS token requests.

# Helper: store or update a secret in a connector vault (idempotent)
store_or_update_secret() {
  local MGMT_URL="$1"
  local SECRET_ID="$2"
  local SECRET_VALUE="$3"

  local RESPONSE
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${MGMT_URL}/v3/secrets" \
    -H "Content-Type: application/json" \
    -H "x-api-key: password" \
    -d "{
      \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
      \"@type\": \"Secret\",
      \"@id\": \"${SECRET_ID}\",
      \"value\": \"${SECRET_VALUE}\"
    }")
  local HTTP_CODE
  HTTP_CODE=$(echo "$RESPONSE" | tail -1)

  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
    echo " created"
  elif [ "$HTTP_CODE" = "409" ]; then
    # Secret already exists — update it with PUT
    RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "${MGMT_URL}/v3/secrets" \
      -H "Content-Type: application/json" \
      -H "x-api-key: password" \
      -d "{
        \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
        \"@type\": \"Secret\",
        \"@id\": \"${SECRET_ID}\",
        \"value\": \"${SECRET_VALUE}\"
      }")
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
      echo " updated (was stale)"
    else
      echo " FAILED to update (HTTP ${HTTP_CODE}): $(echo "$RESPONSE" | sed '$d')"
    fi
  else
    echo " FAILED (HTTP ${HTTP_CODE}): $(echo "$RESPONSE" | sed '$d')"
  fi
}

# Store the STS client secret in the participant-1 connector vault
echo "Storing STS client secret in participant-1 connector..."
store_or_update_secret "${P1_MGMT}" "${P1_DID}-sts-client-secret" "${P1_CLIENT_SECRET}"

# Store the STS client secret in the participant-2 connector vault
echo "Storing STS client secret in participant-2 connector..."
store_or_update_secret "${P2_MGMT}" "${P2_DID}-sts-client-secret" "${P2_CLIENT_SECRET}"

echo ""
echo "=== Storing Membership Credentials ==="

# Store the pre-signed MembershipCredential VC in each participant's IdentityHub
# We need the participant's API key for this. If we have it from above, use it.
# Otherwise, use the superuser key to access the credentials API.

# For simplicity, we use the superuser key with participant ID in the path

# Helper function to build a credential storage request from a VC JWT
store_credential() {
  local IH_IDENTITY="$1"
  local PARTICIPANT_DID="$2"
  local PARTICIPANT_DID_B64="$3"
  local VC_JWT="$4"

  # Decode JWT payload to extract VC fields and build the request manifest
  python3 -c "
import base64, json, sys
jwt = sys.argv[1]
participant_did = sys.argv[2]
payload = jwt.split('.')[1]
payload += '=' * (4 - len(payload) % 4)
decoded = json.loads(base64.urlsafe_b64decode(payload))
vc = decoded['vc']
credential = {
    'id': vc.get('id'),
    'type': vc.get('type', []),
    'issuer': {'id': vc.get('issuer') if isinstance(vc.get('issuer'), str) else vc.get('issuer', {}).get('id')},
    'issuanceDate': vc.get('issuanceDate'),
    'expirationDate': vc.get('expirationDate'),
    'credentialSubject': [vc.get('credentialSubject')] if isinstance(vc.get('credentialSubject'), dict) else vc.get('credentialSubject', [])
}
manifest = {
    'id': 'membership-credential',
    'participantContextId': participant_did,
    'verifiableCredentialContainer': {
        'rawVc': jwt,
        'format': 'VC1_0_JWT',
        'credential': credential
    }
}
print(json.dumps(manifest))
" "$VC_JWT" "$PARTICIPANT_DID" > /tmp/vc-manifest.json

  curl -s -X POST "${IH_IDENTITY}/v1alpha/participants/${PARTICIPANT_DID_B64}/credentials" \
    -H "Content-Type: application/json" \
    -H "x-api-key: ${SUPERUSER_KEY}" \
    -d @/tmp/vc-manifest.json
}

# Store participant-1's VC
echo "Storing participant-1 MembershipCredential..."
store_credential "${P1_IH_IDENTITY}" "${P1_DID}" "${P1_DID_B64}" "${P1_VC_JWT}" && echo " OK" || echo " FAILED"

# Store participant-2's VC
echo "Storing participant-2 MembershipCredential..."
store_credential "${P2_IH_IDENTITY}" "${P2_DID}" "${P2_DID_B64}" "${P2_VC_JWT}" && echo " OK" || echo " FAILED"

echo ""
echo "=== Seeding Complete ==="
echo "You can now use the Insomnia collection to run the E2E dataspace flow."
