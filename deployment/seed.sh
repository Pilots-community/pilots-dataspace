#!/bin/bash
set -euo pipefail

# Seed identity data into IdentityHubs after they start.
# Usage: ./deployment/seed.sh
#
# Prerequisites: IdentityHubs and connectors must be running and healthy.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPERUSER_KEY="c3VwZXItdXNlcg==.superuser-token"

PROVIDER_IH_IDENTITY="http://localhost:7092/api/identity"
CONSUMER_IH_IDENTITY="http://localhost:7082/api/identity"

PROVIDER_IH_DID_PORT=7093
CONSUMER_IH_DID_PORT=7083

PROVIDER_DID="did:web:provider-identityhub%3A${PROVIDER_IH_DID_PORT}"
CONSUMER_DID="did:web:consumer-identityhub%3A${CONSUMER_IH_DID_PORT}"

# Management API endpoints (for storing STS client secrets)
PROVIDER_MGMT="http://localhost:19193/management"
CONSUMER_MGMT="http://localhost:29193/management"

PROVIDER_VC_JWT=$(jq -r '.credential' "${SCRIPT_DIR}/assets/credentials/provider/membership-credential.json")
CONSUMER_VC_JWT=$(jq -r '.credential' "${SCRIPT_DIR}/assets/credentials/consumer/membership-credential.json")

# Base64-encoded participant IDs for API URL paths
PROVIDER_DID_B64=$(echo -n "${PROVIDER_DID}" | base64)
CONSUMER_DID_B64=$(echo -n "${CONSUMER_DID}" | base64)

# DSP protocol endpoints (used for DID document service entries)
PROVIDER_DSP="http://provider-controlplane:19194/protocol"
CONSUMER_DSP="http://consumer-controlplane:29194/protocol"

# CredentialService endpoints (IdentityHub credentials API with base64-encoded DID)
PROVIDER_CREDENTIAL_SVC="http://provider-identityhub:7091/api/credentials/v1/participants/${PROVIDER_DID_B64}"
CONSUMER_CREDENTIAL_SVC="http://consumer-identityhub:7081/api/credentials/v1/participants/${CONSUMER_DID_B64}"

echo "=== Seeding Provider IdentityHub ==="

# Create provider participant context
echo "Creating provider participant context..."
PROVIDER_RESULT=$(curl -s -w "\n%{http_code}" -X POST "${PROVIDER_IH_IDENTITY}/v1alpha/participants" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${SUPERUSER_KEY}" \
  -d "{
    \"participantContextId\": \"${PROVIDER_DID}\",
    \"did\": \"${PROVIDER_DID}\",
    \"active\": true,
    \"key\": {
      \"keyId\": \"${PROVIDER_DID}#key-1\",
      \"privateKeyAlias\": \"${PROVIDER_DID}-alias\",
      \"keyGeneratorParams\": {
        \"algorithm\": \"EdDSA\",
        \"curve\": \"Ed25519\"
      }
    },
    \"serviceEndpoints\": [
      {
        \"type\": \"CredentialService\",
        \"serviceEndpoint\": \"${PROVIDER_CREDENTIAL_SVC}\",
        \"id\": \"provider-credentialservice-1\"
      },
      {
        \"type\": \"ProtocolEndpoint\",
        \"serviceEndpoint\": \"${PROVIDER_DSP}\",
        \"id\": \"provider-dsp\"
      }
    ],
    \"roles\": []
  }")

PROVIDER_HTTP_CODE=$(echo "$PROVIDER_RESULT" | tail -1)
PROVIDER_BODY=$(echo "$PROVIDER_RESULT" | sed '$d')
echo "  HTTP ${PROVIDER_HTTP_CODE}: ${PROVIDER_BODY}"

# Extract the provider API key and STS client secret for later use
if [ "$PROVIDER_HTTP_CODE" = "200" ] || [ "$PROVIDER_HTTP_CODE" = "201" ] || [ "$PROVIDER_HTTP_CODE" = "204" ]; then
  PROVIDER_API_KEY=$(echo "$PROVIDER_BODY" | jq -r '.apiKey // empty' 2>/dev/null || echo "")
  PROVIDER_CLIENT_SECRET=$(echo "$PROVIDER_BODY" | jq -r '.clientSecret // empty' 2>/dev/null || echo "")
  if [ -n "$PROVIDER_API_KEY" ]; then
    echo "  Provider API Key: ${PROVIDER_API_KEY}"
  fi
fi

echo ""
echo "=== Seeding Consumer IdentityHub ==="

# Create consumer participant context
echo "Creating consumer participant context..."
CONSUMER_RESULT=$(curl -s -w "\n%{http_code}" -X POST "${CONSUMER_IH_IDENTITY}/v1alpha/participants" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${SUPERUSER_KEY}" \
  -d "{
    \"participantContextId\": \"${CONSUMER_DID}\",
    \"did\": \"${CONSUMER_DID}\",
    \"active\": true,
    \"key\": {
      \"keyId\": \"${CONSUMER_DID}#key-1\",
      \"privateKeyAlias\": \"${CONSUMER_DID}-alias\",
      \"keyGeneratorParams\": {
        \"algorithm\": \"EdDSA\",
        \"curve\": \"Ed25519\"
      }
    },
    \"serviceEndpoints\": [
      {
        \"type\": \"CredentialService\",
        \"serviceEndpoint\": \"${CONSUMER_CREDENTIAL_SVC}\",
        \"id\": \"consumer-credentialservice-1\"
      },
      {
        \"type\": \"ProtocolEndpoint\",
        \"serviceEndpoint\": \"${CONSUMER_DSP}\",
        \"id\": \"consumer-dsp\"
      }
    ],
    \"roles\": []
  }")

CONSUMER_HTTP_CODE=$(echo "$CONSUMER_RESULT" | tail -1)
CONSUMER_BODY=$(echo "$CONSUMER_RESULT" | sed '$d')
echo "  HTTP ${CONSUMER_HTTP_CODE}: ${CONSUMER_BODY}"

if [ "$CONSUMER_HTTP_CODE" = "200" ] || [ "$CONSUMER_HTTP_CODE" = "201" ] || [ "$CONSUMER_HTTP_CODE" = "204" ]; then
  CONSUMER_API_KEY=$(echo "$CONSUMER_BODY" | jq -r '.apiKey // empty' 2>/dev/null || echo "")
  CONSUMER_CLIENT_SECRET=$(echo "$CONSUMER_BODY" | jq -r '.clientSecret // empty' 2>/dev/null || echo "")
  if [ -n "$CONSUMER_API_KEY" ]; then
    echo "  Consumer API Key: ${CONSUMER_API_KEY}"
  fi
fi

echo ""
echo "=== Activating Participant Contexts ==="

# Participant contexts start in CREATED state. We must activate them before
# DID publishing or STS authentication will work.
echo "Activating provider participant context..."
curl -s -w " HTTP %{http_code}" -X POST "${PROVIDER_IH_IDENTITY}/v1alpha/participants/${PROVIDER_DID_B64}/state?isActive=true" \
  -H "x-api-key: ${SUPERUSER_KEY}" && echo "" || echo " FAILED"

echo "Activating consumer participant context..."
curl -s -w " HTTP %{http_code}" -X POST "${CONSUMER_IH_IDENTITY}/v1alpha/participants/${CONSUMER_DID_B64}/state?isActive=true" \
  -H "x-api-key: ${SUPERUSER_KEY}" && echo "" || echo " FAILED"

echo ""
echo "=== Publishing DID Documents ==="

# Publish DIDs so they're resolvable via did:web
echo "Publishing provider DID..."
curl -s -w " HTTP %{http_code}" -X POST "${PROVIDER_IH_IDENTITY}/v1alpha/participants/${PROVIDER_DID_B64}/dids/publish" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${SUPERUSER_KEY}" \
  -d "{\"did\": \"${PROVIDER_DID}\"}" && echo "" || echo " FAILED"

echo "Publishing consumer DID..."
curl -s -w " HTTP %{http_code}" -X POST "${CONSUMER_IH_IDENTITY}/v1alpha/participants/${CONSUMER_DID_B64}/dids/publish" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${SUPERUSER_KEY}" \
  -d "{\"did\": \"${CONSUMER_DID}\"}" && echo "" || echo " FAILED"

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

# Store the STS client secret in the provider connector vault
echo "Storing STS client secret in provider connector..."
store_or_update_secret "${PROVIDER_MGMT}" "${PROVIDER_DID}-sts-client-secret" "${PROVIDER_CLIENT_SECRET}"

# Store the STS client secret in the consumer connector vault
echo "Storing STS client secret in consumer connector..."
store_or_update_secret "${CONSUMER_MGMT}" "${CONSUMER_DID}-sts-client-secret" "${CONSUMER_CLIENT_SECRET}"

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

# Store provider's VC
echo "Storing provider MembershipCredential..."
store_credential "${PROVIDER_IH_IDENTITY}" "${PROVIDER_DID}" "${PROVIDER_DID_B64}" "${PROVIDER_VC_JWT}" && echo " OK" || echo " FAILED"

# Store consumer's VC
echo "Storing consumer MembershipCredential..."
store_credential "${CONSUMER_IH_IDENTITY}" "${CONSUMER_DID}" "${CONSUMER_DID_B64}" "${CONSUMER_VC_JWT}" && echo " OK" || echo " FAILED"

echo ""
echo "=== Seeding Complete ==="
echo "You can now use the Insomnia collection to run the E2E dataspace flow."
