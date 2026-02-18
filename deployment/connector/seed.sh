#!/bin/bash
set -euo pipefail

# Seed identity data for a standalone connector deployment.
# Usage: MY_PUBLIC_HOST=<ip> ./seed.sh
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

IH_IDENTITY="http://localhost:7092/api/identity"

DID="did:web:${MY_PUBLIC_HOST}%3A7093"
ISSUER_DID="did:web:${MY_PUBLIC_HOST}%3A9876"

MGMT="http://localhost:19193/management"

DID_B64=$(echo -n "${DID}" | base64)

# Service endpoints use public host
DSP="http://${MY_PUBLIC_HOST}:19194/protocol"
CREDENTIAL_SVC="http://${MY_PUBLIC_HOST}:7091/api/credentials/v1/participants/${DID_B64}"

# Generate VC dynamically — DIDs depend on MY_PUBLIC_HOST
echo "=== Generating Membership Credential ==="
ISSUER_KEY="${REPO_ROOT}/deployment/assets/issuer_private.pem"
if [ ! -f "$ISSUER_KEY" ]; then
  echo "ERROR: Issuer private key not found at $ISSUER_KEY"
  echo "Run ./generate-keys.sh from the project root first."
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

VC_JWT=$(generate_vc "${DID}" "Connector" "urn:uuid:$(python3 -c 'import uuid; print(uuid.uuid4())')")
echo "  Generated VC for ${DID}"

echo ""
echo "=== Seeding IdentityHub ==="

echo "Creating participant context..."
RESULT=$(curl -s -w "\n%{http_code}" -X POST "${IH_IDENTITY}/v1alpha/participants" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${SUPERUSER_KEY}" \
  -d "{
    \"participantContextId\": \"${DID}\",
    \"did\": \"${DID}\",
    \"active\": true,
    \"key\": {
      \"keyId\": \"${DID}#key-1\",
      \"privateKeyAlias\": \"${DID}-alias\",
      \"keyGeneratorParams\": {
        \"algorithm\": \"EdDSA\",
        \"curve\": \"Ed25519\"
      }
    },
    \"serviceEndpoints\": [
      {
        \"type\": \"CredentialService\",
        \"serviceEndpoint\": \"${CREDENTIAL_SVC}\",
        \"id\": \"connector-credentialservice-1\"
      },
      {
        \"type\": \"ProtocolEndpoint\",
        \"serviceEndpoint\": \"${DSP}\",
        \"id\": \"connector-dsp\"
      }
    ],
    \"roles\": []
  }")

HTTP_CODE=$(echo "$RESULT" | tail -1)
BODY=$(echo "$RESULT" | sed '$d')
echo "  HTTP ${HTTP_CODE}: ${BODY}"

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "204" ]; then
  CLIENT_SECRET=$(echo "$BODY" | jq -r '.clientSecret // empty' 2>/dev/null || echo "")
fi

echo ""
echo "=== Activating Participant Context ==="

echo "Activating participant context..."
curl -s -w " HTTP %{http_code}" -X POST "${IH_IDENTITY}/v1alpha/participants/${DID_B64}/state?isActive=true" \
  -H "x-api-key: ${SUPERUSER_KEY}" && echo "" || echo " FAILED"

echo ""
echo "=== Publishing DID Document ==="

echo "Publishing DID..."
curl -s -w " HTTP %{http_code}" -X POST "${IH_IDENTITY}/v1alpha/participants/${DID_B64}/dids/publish" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${SUPERUSER_KEY}" \
  -d "{\"did\": \"${DID}\"}" && echo "" || echo " FAILED"

echo ""
echo "=== Storing STS Client Secret ==="

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

echo "Storing STS client secret in connector..."
store_or_update_secret "${MGMT}" "${DID}-sts-client-secret" "${CLIENT_SECRET}"

echo ""
echo "=== Storing Membership Credential ==="

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

echo "Storing MembershipCredential..."
store_credential "${IH_IDENTITY}" "${DID}" "${DID_B64}" "${VC_JWT}" && echo " OK" || echo " FAILED"

echo ""
echo "=== Updating Issuer DID Document ==="
# The issuer DID must match the trusted issuer configured in the controlplane.
# In standalone mode, each machine is its own issuer, so the issuer DID uses
# the public host. We update the static DID document served by nginx.
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
echo "Connector DID: ${DID}"
echo "Issuer DID:    ${ISSUER_DID}"
echo ""
echo "This machine's issuer DID document is served at:"
echo "  http://${MY_PUBLIC_HOST}:9876/.well-known/did.json"
echo ""
echo "Other machines will resolve this to verify VCs signed by this machine."
echo ""
echo "Test catalog request from another machine (replace <REMOTE_HOST> and <REMOTE_DID>):"
echo "  curl -X POST http://localhost:19193/management/v3/catalog/request \\"
echo "    -H 'Content-Type: application/json' -H 'x-api-key: password' \\"
echo "    -d '{\"@context\":{\"@vocab\":\"https://w3id.org/edc/v0.0.1/ns/\"},\"@type\":\"CatalogRequest\",\"counterPartyAddress\":\"http://<REMOTE_HOST>:19194/protocol\",\"counterPartyId\":\"did:web:<REMOTE_HOST>%3A7093\",\"protocol\":\"dataspace-protocol-http\"}'"
