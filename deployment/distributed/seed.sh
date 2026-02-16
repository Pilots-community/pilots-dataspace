#!/bin/bash
set -euo pipefail

# Seed identity data for distributed DCP dataspace.
# Usage: MY_PUBLIC_HOST=<ip> ./deployment/distributed/seed.sh
#
# MY_PUBLIC_HOST must match the value used in docker compose.

if [ -z "${MY_PUBLIC_HOST:-}" ]; then
  echo "ERROR: MY_PUBLIC_HOST is not set."
  echo "Usage: MY_PUBLIC_HOST=<ip> $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SUPERUSER_KEY="c3VwZXItdXNlcg==.superuser-token"

P1_IH_IDENTITY="http://localhost:7092/api/identity"
P2_IH_IDENTITY="http://localhost:7082/api/identity"

P1_DID="did:web:${MY_PUBLIC_HOST}%3A7093"
P2_DID="did:web:${MY_PUBLIC_HOST}%3A7083"
ISSUER_DID="did:web:${MY_PUBLIC_HOST}%3A9876"

P1_MGMT="http://localhost:19193/management"
P2_MGMT="http://localhost:29193/management"

P1_DID_B64=$(echo -n "${P1_DID}" | base64)
P2_DID_B64=$(echo -n "${P2_DID}" | base64)

# Service endpoints use public host
P1_DSP="http://${MY_PUBLIC_HOST}:19194/protocol"
P2_DSP="http://${MY_PUBLIC_HOST}:29194/protocol"
P1_CREDENTIAL_SVC="http://${MY_PUBLIC_HOST}:7091/api/credentials/v1/participants/${P1_DID_B64}"
P2_CREDENTIAL_SVC="http://${MY_PUBLIC_HOST}:7081/api/credentials/v1/participants/${P2_DID_B64}"

# Generate VCs dynamically — DIDs depend on MY_PUBLIC_HOST
echo "=== Generating Membership Credentials ==="
ISSUER_KEY="${REPO_ROOT}/deployment/assets/issuer_private.pem"
if [ ! -f "$ISSUER_KEY" ]; then
  echo "ERROR: Issuer private key not found at $ISSUER_KEY"
  exit 1
fi

generate_vc() {
  local SUBJECT_DID="$1"
  local NAME="$2"
  local JTI="$3"
  /usr/bin/python3 -c "
import json, base64, time
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
import sys

with open(sys.argv[1], 'rb') as f:
    pk = serialization.load_pem_private_key(f.read(), password=None)

def b64e(d): return base64.urlsafe_b64encode(d).rstrip(b'=').decode()

hdr = {'alg':'ES256','kid':'${ISSUER_DID}#issuer-key-1','typ':'JWT'}
now = int(time.time())
payload = {
    'iss': '${ISSUER_DID}', 'sub': sys.argv[2],
    'iat': now, 'exp': now + 10*365*24*3600, 'jti': sys.argv[4],
    'vc': {
        '@context': ['https://www.w3.org/2018/credentials/v1','https://w3id.org/security/suites/jws-2020/v1','https://www.w3.org/ns/credentials/examples/v1'],
        'id': sys.argv[4],
        'type': ['VerifiableCredential','MembershipCredential'],
        'issuer': '${ISSUER_DID}',
        'issuanceDate': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(now)),
        'expirationDate': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(now + 10*365*24*3600)),
        'credentialSubject': {'id': sys.argv[2], 'memberOf': 'dataspace-pilots', 'name': sys.argv[3], 'status': 'Active Member'}
    }
}
h = b64e(json.dumps(hdr,separators=(',',':')).encode())
p = b64e(json.dumps(payload,separators=(',',':')).encode())
sig = pk.sign(f'{h}.{p}'.encode(), ec.ECDSA(hashes.SHA256()))
r,s = decode_dss_signature(sig)
print(f'{h}.{p}.{b64e(r.to_bytes(32,\"big\")+s.to_bytes(32,\"big\"))}')
" "$ISSUER_KEY" "$SUBJECT_DID" "$NAME" "$JTI"
}

P1_VC_JWT=$(generate_vc "${P1_DID}" "Participant 1" "urn:uuid:75da308a-ea17-434c-8618-e1aeb0c6fad1")
P2_VC_JWT=$(generate_vc "${P2_DID}" "Participant 2" "urn:uuid:85da308a-ea17-434c-8618-e1aeb0c6fad2")
echo "  Generated VCs for ${P1_DID} and ${P2_DID}"

echo ""
echo "=== Seeding Participant-1 IdentityHub ==="

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

if [ "$P1_HTTP_CODE" = "200" ] || [ "$P1_HTTP_CODE" = "201" ] || [ "$P1_HTTP_CODE" = "204" ]; then
  P1_CLIENT_SECRET=$(echo "$P1_BODY" | jq -r '.clientSecret // empty' 2>/dev/null || echo "")
fi

echo ""
echo "=== Seeding Participant-2 IdentityHub ==="

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
  P2_CLIENT_SECRET=$(echo "$P2_BODY" | jq -r '.clientSecret // empty' 2>/dev/null || echo "")
fi

echo ""
echo "=== Activating Participant Contexts ==="

echo "Activating participant-1 participant context..."
curl -s -w " HTTP %{http_code}" -X POST "${P1_IH_IDENTITY}/v1alpha/participants/${P1_DID_B64}/state?isActive=true" \
  -H "x-api-key: ${SUPERUSER_KEY}" && echo "" || echo " FAILED"

echo "Activating participant-2 participant context..."
curl -s -w " HTTP %{http_code}" -X POST "${P2_IH_IDENTITY}/v1alpha/participants/${P2_DID_B64}/state?isActive=true" \
  -H "x-api-key: ${SUPERUSER_KEY}" && echo "" || echo " FAILED"

echo ""
echo "=== Publishing DID Documents ==="

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

echo "Storing STS client secret in participant-1 connector..."
store_or_update_secret "${P1_MGMT}" "${P1_DID}-sts-client-secret" "${P1_CLIENT_SECRET}"

echo "Storing STS client secret in participant-2 connector..."
store_or_update_secret "${P2_MGMT}" "${P2_DID}-sts-client-secret" "${P2_CLIENT_SECRET}"

echo ""
echo "=== Storing Membership Credentials ==="

store_credential() {
  local IH_IDENTITY="$1"
  local PARTICIPANT_DID="$2"
  local PARTICIPANT_DID_B64="$3"
  local VC_JWT="$4"

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

echo "Storing participant-1 MembershipCredential..."
store_credential "${P1_IH_IDENTITY}" "${P1_DID}" "${P1_DID_B64}" "${P1_VC_JWT}" && echo " OK" || echo " FAILED"

echo "Storing participant-2 MembershipCredential..."
store_credential "${P2_IH_IDENTITY}" "${P2_DID}" "${P2_DID_B64}" "${P2_VC_JWT}" && echo " OK" || echo " FAILED"

echo ""
echo "=== Updating Issuer DID Document ==="
# The issuer DID must match the trusted issuer configured in the controlplanes.
# In distributed mode, the issuer DID uses the public host, so we update the
# static DID document served by nginx to use the matching DID and key IDs.
echo "Issuer DID: ${ISSUER_DID}"

# Read the public key from the issuer private key
ISSUER_PUB_JWK=$(/usr/bin/python3 -c "
from cryptography.hazmat.primitives import serialization
import base64, json, sys

with open(sys.argv[1], 'rb') as f:
    pk = serialization.load_pem_private_key(f.read(), password=None)

pub = pk.public_key()
nums = pub.public_numbers()

def b64e(n, length):
    return base64.urlsafe_b64encode(n.to_bytes(length, 'big')).rstrip(b'=').decode()

print(json.dumps({
    'kty': 'EC', 'crv': 'P-256',
    'x': b64e(nums.x, 32), 'y': b64e(nums.y, 32),
    'kid': 'issuer-key-1'
}))
" "$ISSUER_KEY")

# Generate the DID document with the correct DID
cat > /tmp/issuer-did.json <<DIDJSON
{
  "@context": [
    "https://www.w3.org/ns/did/v1",
    "https://w3id.org/security/suites/jws-2020/v1"
  ],
  "id": "${ISSUER_DID}",
  "verificationMethod": [
    {
      "id": "${ISSUER_DID}#issuer-key-1",
      "type": "JsonWebKey2020",
      "controller": "${ISSUER_DID}",
      "publicKeyJwk": ${ISSUER_PUB_JWK}
    }
  ],
  "authentication": [
    "${ISSUER_DID}#issuer-key-1"
  ],
  "assertionMethod": [
    "${ISSUER_DID}#issuer-key-1"
  ]
}
DIDJSON

echo "Copying updated DID document into did-server container..."
docker cp /tmp/issuer-did.json did-server:/usr/share/nginx/html/.well-known/did.json
echo "  Verifying: $(curl -s http://localhost:9876/.well-known/did.json | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"

echo ""
echo "=== Seeding Complete ==="
echo "Participant-1 DID: ${P1_DID}"
echo "Participant-2 DID: ${P2_DID}"
echo "Issuer DID:   ${ISSUER_DID}"
echo ""
echo "Test with:"
echo "  curl -X POST http://localhost:29193/management/v3/catalog/request \\"
echo "    -H 'Content-Type: application/json' -H 'x-api-key: password' \\"
echo "    -d '{\"@context\":{\"@vocab\":\"https://w3id.org/edc/v0.0.1/ns/\"},\"@type\":\"CatalogRequest\",\"counterPartyAddress\":\"http://${MY_PUBLIC_HOST}:19194/protocol\",\"counterPartyId\":\"${P1_DID}\",\"protocol\":\"dataspace-protocol-http\"}'"
