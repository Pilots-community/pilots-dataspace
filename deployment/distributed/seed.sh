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

PROVIDER_IH_IDENTITY="http://localhost:7092/api/identity"
CONSUMER_IH_IDENTITY="http://localhost:7082/api/identity"

PROVIDER_DID="did:web:${MY_PUBLIC_HOST}%3A7093"
CONSUMER_DID="did:web:${MY_PUBLIC_HOST}%3A7083"
ISSUER_DID="did:web:${MY_PUBLIC_HOST}%3A9876"

PROVIDER_MGMT="http://localhost:19193/management"
CONSUMER_MGMT="http://localhost:29193/management"

PROVIDER_DID_B64=$(echo -n "${PROVIDER_DID}" | base64)
CONSUMER_DID_B64=$(echo -n "${CONSUMER_DID}" | base64)

# Service endpoints use public host
PROVIDER_DSP="http://${MY_PUBLIC_HOST}:19194/protocol"
CONSUMER_DSP="http://${MY_PUBLIC_HOST}:29194/protocol"
PROVIDER_CREDENTIAL_SVC="http://${MY_PUBLIC_HOST}:7091/api/credentials/v1/participants/${PROVIDER_DID_B64}"
CONSUMER_CREDENTIAL_SVC="http://${MY_PUBLIC_HOST}:7081/api/credentials/v1/participants/${CONSUMER_DID_B64}"

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

PROVIDER_VC_JWT=$(generate_vc "${PROVIDER_DID}" "Provider" "urn:uuid:75da308a-ea17-434c-8618-e1aeb0c6fad1")
CONSUMER_VC_JWT=$(generate_vc "${CONSUMER_DID}" "Consumer" "urn:uuid:85da308a-ea17-434c-8618-e1aeb0c6fad2")
echo "  Generated VCs for ${PROVIDER_DID} and ${CONSUMER_DID}"

echo ""
echo "=== Seeding Provider IdentityHub ==="

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
PROVIDER_BODY=$(echo "$PROVIDER_RESULT" | head -n -1)
echo "  HTTP ${PROVIDER_HTTP_CODE}: ${PROVIDER_BODY}"

if [ "$PROVIDER_HTTP_CODE" = "200" ] || [ "$PROVIDER_HTTP_CODE" = "201" ] || [ "$PROVIDER_HTTP_CODE" = "204" ]; then
  PROVIDER_CLIENT_SECRET=$(echo "$PROVIDER_BODY" | jq -r '.clientSecret // empty' 2>/dev/null || echo "")
fi

echo ""
echo "=== Seeding Consumer IdentityHub ==="

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
CONSUMER_BODY=$(echo "$CONSUMER_RESULT" | head -n -1)
echo "  HTTP ${CONSUMER_HTTP_CODE}: ${CONSUMER_BODY}"

if [ "$CONSUMER_HTTP_CODE" = "200" ] || [ "$CONSUMER_HTTP_CODE" = "201" ] || [ "$CONSUMER_HTTP_CODE" = "204" ]; then
  CONSUMER_CLIENT_SECRET=$(echo "$CONSUMER_BODY" | jq -r '.clientSecret // empty' 2>/dev/null || echo "")
fi

echo ""
echo "=== Activating Participant Contexts ==="

echo "Activating provider participant context..."
curl -s -w " HTTP %{http_code}" -X POST "${PROVIDER_IH_IDENTITY}/v1alpha/participants/${PROVIDER_DID_B64}/state?isActive=true" \
  -H "x-api-key: ${SUPERUSER_KEY}" && echo "" || echo " FAILED"

echo "Activating consumer participant context..."
curl -s -w " HTTP %{http_code}" -X POST "${CONSUMER_IH_IDENTITY}/v1alpha/participants/${CONSUMER_DID_B64}/state?isActive=true" \
  -H "x-api-key: ${SUPERUSER_KEY}" && echo "" || echo " FAILED"

echo ""
echo "=== Publishing DID Documents ==="

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

echo "Storing STS client secret in provider connector..."
curl -s -X POST "${PROVIDER_MGMT}/v3/secrets" \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d "{
    \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
    \"@type\": \"Secret\",
    \"@id\": \"${PROVIDER_DID}-sts-client-secret\",
    \"value\": \"${PROVIDER_CLIENT_SECRET}\"
  }" && echo " OK" || echo " FAILED"

echo "Storing STS client secret in consumer connector..."
curl -s -X POST "${CONSUMER_MGMT}/v3/secrets" \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d "{
    \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
    \"@type\": \"Secret\",
    \"@id\": \"${CONSUMER_DID}-sts-client-secret\",
    \"value\": \"${CONSUMER_CLIENT_SECRET}\"
  }" && echo " OK" || echo " FAILED"

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

echo "Storing provider MembershipCredential..."
store_credential "${PROVIDER_IH_IDENTITY}" "${PROVIDER_DID}" "${PROVIDER_DID_B64}" "${PROVIDER_VC_JWT}" && echo " OK" || echo " FAILED"

echo "Storing consumer MembershipCredential..."
store_credential "${CONSUMER_IH_IDENTITY}" "${CONSUMER_DID}" "${CONSUMER_DID_B64}" "${CONSUMER_VC_JWT}" && echo " OK" || echo " FAILED"

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
echo "Provider DID: ${PROVIDER_DID}"
echo "Consumer DID: ${CONSUMER_DID}"
echo "Issuer DID:   ${ISSUER_DID}"
echo ""
echo "Test with:"
echo "  curl -X POST http://localhost:29193/management/v3/catalog/request \\"
echo "    -H 'Content-Type: application/json' -H 'x-api-key: password' \\"
echo "    -d '{\"@context\":{\"@vocab\":\"https://w3id.org/edc/v0.0.1/ns/\"},\"@type\":\"CatalogRequest\",\"counterPartyAddress\":\"http://${MY_PUBLIC_HOST}:19194/protocol\",\"counterPartyId\":\"${PROVIDER_DID}\",\"protocol\":\"dataspace-protocol-http\"}'"
