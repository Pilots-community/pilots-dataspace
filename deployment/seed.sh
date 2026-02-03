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

echo "=== Seeding Provider IdentityHub ==="

# Create provider participant context
echo "Creating provider participant context..."
PROVIDER_RESULT=$(curl -s -w "\n%{http_code}" -X POST "${PROVIDER_IH_IDENTITY}/v1alpha/participants" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${SUPERUSER_KEY}" \
  -d "{
    \"participantId\": \"${PROVIDER_DID}\",
    \"did\": \"${PROVIDER_DID}\",
    \"active\": true,
    \"key\": {
      \"keyId\": \"${PROVIDER_DID}#key-1\",
      \"privateKeyAlias\": \"${PROVIDER_DID}-alias\",
      \"keyGeneratorParams\": {
        \"algorithm\": \"EC\",
        \"curve\": \"secp256r1\"
      }
    },
    \"roles\": []
  }")

PROVIDER_HTTP_CODE=$(echo "$PROVIDER_RESULT" | tail -1)
PROVIDER_BODY=$(echo "$PROVIDER_RESULT" | head -n -1)
echo "  HTTP ${PROVIDER_HTTP_CODE}: ${PROVIDER_BODY}"

# Extract the provider API key for later use
if [ "$PROVIDER_HTTP_CODE" = "200" ] || [ "$PROVIDER_HTTP_CODE" = "201" ] || [ "$PROVIDER_HTTP_CODE" = "204" ]; then
  PROVIDER_API_KEY=$(echo "$PROVIDER_BODY" | jq -r '.apiKey // empty' 2>/dev/null || echo "")
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
    \"participantId\": \"${CONSUMER_DID}\",
    \"did\": \"${CONSUMER_DID}\",
    \"active\": true,
    \"key\": {
      \"keyId\": \"${CONSUMER_DID}#key-1\",
      \"privateKeyAlias\": \"${CONSUMER_DID}-alias\",
      \"keyGeneratorParams\": {
        \"algorithm\": \"EC\",
        \"curve\": \"secp256r1\"
      }
    },
    \"roles\": []
  }")

CONSUMER_HTTP_CODE=$(echo "$CONSUMER_RESULT" | tail -1)
CONSUMER_BODY=$(echo "$CONSUMER_RESULT" | head -n -1)
echo "  HTTP ${CONSUMER_HTTP_CODE}: ${CONSUMER_BODY}"

if [ "$CONSUMER_HTTP_CODE" = "200" ] || [ "$CONSUMER_HTTP_CODE" = "201" ] || [ "$CONSUMER_HTTP_CODE" = "204" ]; then
  CONSUMER_API_KEY=$(echo "$CONSUMER_BODY" | jq -r '.apiKey // empty' 2>/dev/null || echo "")
  if [ -n "$CONSUMER_API_KEY" ]; then
    echo "  Consumer API Key: ${CONSUMER_API_KEY}"
  fi
fi

echo ""
echo "=== Storing STS Client Secrets ==="

# The connector needs an STS client secret to authenticate with the embedded STS in IdentityHub.
# We store it via the Secrets API on the connector's management endpoint.
# The STS client secret must also be stored in the IdentityHub's vault.

STS_CLIENT_SECRET="password"

# Store the STS client secret in the provider connector vault via Secrets API
echo "Storing STS client secret in provider connector..."
curl -s -X POST "${PROVIDER_MGMT}/v3/secrets" \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d "{
    \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
    \"@type\": \"Secret\",
    \"@id\": \"${PROVIDER_DID}-sts-client-secret\",
    \"value\": \"${STS_CLIENT_SECRET}\"
  }" && echo " OK" || echo " FAILED"

# Store the STS client secret in the consumer connector vault via Secrets API
echo "Storing STS client secret in consumer connector..."
curl -s -X POST "${CONSUMER_MGMT}/v3/secrets" \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d "{
    \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
    \"@type\": \"Secret\",
    \"@id\": \"${CONSUMER_DID}-sts-client-secret\",
    \"value\": \"${STS_CLIENT_SECRET}\"
  }" && echo " OK" || echo " FAILED"

echo ""
echo "=== Storing Membership Credentials ==="

# Store the pre-signed MembershipCredential VC in each participant's IdentityHub
# We need the participant's API key for this. If we have it from above, use it.
# Otherwise, use the superuser key to access the credentials API.

# For simplicity, we use the superuser key with participant ID in the path

# Store provider's VC
echo "Storing provider MembershipCredential..."
curl -s -X POST "${PROVIDER_IH_IDENTITY}/v1alpha/participants/${PROVIDER_DID}/credentials" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${SUPERUSER_KEY}" \
  -d "{
    \"credentialId\": \"membership-credential\",
    \"issuerId\": \"did:web:did-server%3A9876\",
    \"holderId\": \"${PROVIDER_DID}\",
    \"issuanceDate\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"expirationDate\": \"2036-01-01T00:00:00Z\",
    \"vcJwt\": \"${PROVIDER_VC_JWT}\",
    \"participantId\": \"${PROVIDER_DID}\"
  }" && echo " OK" || echo " FAILED"

# Store consumer's VC
echo "Storing consumer MembershipCredential..."
curl -s -X POST "${CONSUMER_IH_IDENTITY}/v1alpha/participants/${CONSUMER_DID}/credentials" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${SUPERUSER_KEY}" \
  -d "{
    \"credentialId\": \"membership-credential\",
    \"issuerId\": \"did:web:did-server%3A9876\",
    \"holderId\": \"${CONSUMER_DID}\",
    \"issuanceDate\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"expirationDate\": \"2036-01-01T00:00:00Z\",
    \"vcJwt\": \"${CONSUMER_VC_JWT}\",
    \"participantId\": \"${CONSUMER_DID}\"
  }" && echo " OK" || echo " FAILED"

echo ""
echo "=== Seeding Complete ==="
echo "You can now use the Insomnia collection to run the E2E dataspace flow."
