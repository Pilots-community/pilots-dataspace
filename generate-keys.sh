#!/bin/bash
set -euo pipefail

# Generate all key pairs needed by the dataspace runtimes.
# Run this once before building Docker images or starting services.
#
# Generated files:
#   config/certs/private-key.pem   — Data plane token signing (EC P-256)
#   config/certs/public-key.pem    — Data plane token verification
#
#   Standalone deployment (single issuer):
#     deployment/assets/issuer_private.pem — VC issuer signing key (EC P-256)
#     deployment/assets/issuer_public.pem  — VC issuer public key
#     deployment/assets/issuer/did.json    — Issuer DID document
#
#   Dev deployment (per-participant issuers):
#     deployment/assets/participant-{1,2}/issuer_private.pem — Per-participant issuer keys
#     deployment/assets/participant-{1,2}/issuer_public.pem
#     deployment/assets/participant-{1,2}/issuer/did.json    — Per-participant issuer DID docs
#
#   deployment/assets/credentials/       — Pre-signed Verifiable Credential JWTs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find a python3 with the cryptography library
PYTHON=python3
if ! "$PYTHON" -c "from cryptography.hazmat.primitives import serialization" 2>/dev/null; then
  if /usr/bin/python3 -c "from cryptography.hazmat.primitives import serialization" 2>/dev/null; then
    PYTHON=/usr/bin/python3
  else
    echo "ERROR: Python 3 'cryptography' library not found."
    echo "Install with: pip install cryptography"
    exit 1
  fi
fi

echo "=== Generating Data Plane Token Signing Keys ==="
mkdir -p "${SCRIPT_DIR}/config/certs"

if [ -f "${SCRIPT_DIR}/config/certs/private-key.pem" ]; then
  echo "  Already exist, skipping (delete to regenerate)"
else
  openssl ecparam -name prime256v1 -genkey -noout | \
    openssl pkcs8 -topk8 -nocrypt -out "${SCRIPT_DIR}/config/certs/private-key.pem"
  openssl ec -in "${SCRIPT_DIR}/config/certs/private-key.pem" -pubout \
    -out "${SCRIPT_DIR}/config/certs/public-key.pem" 2>/dev/null
  echo "  Created config/certs/private-key.pem"
  echo "  Created config/certs/public-key.pem"
fi

# --- Standalone issuer keys (single issuer for deployment/connector) ---

echo ""
echo "=== Generating VC Issuer Keys (standalone) ==="
mkdir -p "${SCRIPT_DIR}/deployment/assets"

if [ -f "${SCRIPT_DIR}/deployment/assets/issuer_private.pem" ]; then
  echo "  Already exist, skipping (delete to regenerate)"
else
  openssl ecparam -name prime256v1 -genkey -noout | \
    openssl pkcs8 -topk8 -nocrypt -out "${SCRIPT_DIR}/deployment/assets/issuer_private.pem"
  openssl ec -in "${SCRIPT_DIR}/deployment/assets/issuer_private.pem" -pubout \
    -out "${SCRIPT_DIR}/deployment/assets/issuer_public.pem" 2>/dev/null
  echo "  Created deployment/assets/issuer_private.pem"
  echo "  Created deployment/assets/issuer_public.pem"
fi

echo ""
echo "=== Updating Issuer DID Document (standalone) ==="

# Helper: generate an issuer DID document from a private key
generate_did_document() {
  local PRIVATE_KEY="$1"
  local DID_ID="$2"
  local OUTPUT="$3"

  mkdir -p "$(dirname "$OUTPUT")"

  "$PYTHON" -c "
from cryptography.hazmat.primitives import serialization
import base64, json, sys

with open(sys.argv[1], 'rb') as f:
    pk = serialization.load_pem_private_key(f.read(), password=None)

pub = pk.public_key()
nums = pub.public_numbers()

def b64e(n, length):
    return base64.urlsafe_b64encode(n.to_bytes(length, 'big')).rstrip(b'=').decode()

did_id = sys.argv[2]
jwk = {
    'kty': 'EC', 'crv': 'P-256',
    'x': b64e(nums.x, 32), 'y': b64e(nums.y, 32),
    'kid': 'issuer-key-1'
}

did_doc = {
    '@context': [
        'https://www.w3.org/ns/did/v1',
        'https://w3id.org/security/suites/jws-2020/v1'
    ],
    'id': did_id,
    'verificationMethod': [{
        'id': did_id + '#issuer-key-1',
        'type': 'JsonWebKey2020',
        'controller': did_id,
        'publicKeyJwk': jwk
    }],
    'authentication': [did_id + '#issuer-key-1'],
    'assertionMethod': [did_id + '#issuer-key-1']
}

with open(sys.argv[3], 'w') as f:
    json.dump(did_doc, f, indent=2)
    f.write('\n')
" "$PRIVATE_KEY" "$DID_ID" "$OUTPUT"
}

generate_did_document \
  "${SCRIPT_DIR}/deployment/assets/issuer_private.pem" \
  "did:web:did-server%3A9876" \
  "${SCRIPT_DIR}/deployment/assets/issuer/did.json"
echo "  Updated deployment/assets/issuer/did.json"

# --- Per-participant issuer keys (for dev docker-compose) ---

echo ""
echo "=== Generating Per-Participant Issuer Keys (dev) ==="

for N in 1 2; do
  PARTICIPANT_DIR="${SCRIPT_DIR}/deployment/assets/participant-${N}"
  mkdir -p "${PARTICIPANT_DIR}"

  if [ -f "${PARTICIPANT_DIR}/issuer_private.pem" ]; then
    echo "  participant-${N}: Already exist, skipping (delete to regenerate)"
  else
    openssl ecparam -name prime256v1 -genkey -noout | \
      openssl pkcs8 -topk8 -nocrypt -out "${PARTICIPANT_DIR}/issuer_private.pem"
    openssl ec -in "${PARTICIPANT_DIR}/issuer_private.pem" -pubout \
      -out "${PARTICIPANT_DIR}/issuer_public.pem" 2>/dev/null
    echo "  Created deployment/assets/participant-${N}/issuer_private.pem"
    echo "  Created deployment/assets/participant-${N}/issuer_public.pem"
  fi
done

echo ""
echo "=== Updating Per-Participant Issuer DID Documents (dev) ==="

generate_did_document \
  "${SCRIPT_DIR}/deployment/assets/participant-1/issuer_private.pem" \
  "did:web:participant-1-did-server%3A9876" \
  "${SCRIPT_DIR}/deployment/assets/participant-1/issuer/did.json"
echo "  Updated deployment/assets/participant-1/issuer/did.json"

generate_did_document \
  "${SCRIPT_DIR}/deployment/assets/participant-2/issuer_private.pem" \
  "did:web:participant-2-did-server%3A9876" \
  "${SCRIPT_DIR}/deployment/assets/participant-2/issuer/did.json"
echo "  Updated deployment/assets/participant-2/issuer/did.json"

echo ""
echo "=== Generating Pre-signed VCs ==="

P1_DID="did:web:participant-1-identityhub%3A7093"
P2_DID="did:web:participant-2-identityhub%3A7083"

# Each participant's VC is signed by their own per-participant issuer
P1_ISSUER_DID="did:web:participant-1-did-server%3A9876"
P2_ISSUER_DID="did:web:participant-2-did-server%3A9876"

generate_vc_file() {
  local ISSUER_KEY="$1"
  local ISSUER_DID="$2"
  local SUBJECT_DID="$3"
  local NAME="$4"
  local JTI="$5"
  local OUTPUT="$6"

  mkdir -p "$(dirname "$OUTPUT")"

  "$PYTHON" -c "
import json, base64, time, sys
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

with open(sys.argv[1], 'rb') as f:
    pk = serialization.load_pem_private_key(f.read(), password=None)

def b64e(d): return base64.urlsafe_b64encode(d).rstrip(b'=').decode()

issuer_did = sys.argv[2]
hdr = {'alg':'ES256','kid': issuer_did + '#issuer-key-1','typ':'JWT'}
now = int(time.time())
payload = {
    'iss': issuer_did, 'sub': sys.argv[3],
    'iat': now, 'exp': now + 10*365*24*3600, 'jti': sys.argv[5],
    'vc': {
        '@context': ['https://www.w3.org/2018/credentials/v1','https://w3id.org/security/suites/jws-2020/v1','https://www.w3.org/ns/credentials/examples/v1'],
        'id': sys.argv[5],
        'type': ['VerifiableCredential','MembershipCredential'],
        'issuer': issuer_did,
        'issuanceDate': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(now)),
        'expirationDate': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(now + 10*365*24*3600)),
        'credentialSubject': {'id': sys.argv[3], 'memberOf': 'dataspace-pilots', 'name': sys.argv[4], 'status': 'Active Member'}
    }
}
h = b64e(json.dumps(hdr,separators=(',',':')).encode())
p = b64e(json.dumps(payload,separators=(',',':')).encode())
sig = pk.sign(f'{h}.{p}'.encode(), ec.ECDSA(hashes.SHA256()))
r,s = decode_dss_signature(sig)
jwt_token = f'{h}.{p}.{b64e(r.to_bytes(32,\"big\")+s.to_bytes(32,\"big\"))}'

with open(sys.argv[6], 'w') as f:
    json.dump({'credential': jwt_token}, f, indent=2)
    f.write('\n')
" "$ISSUER_KEY" "$ISSUER_DID" "$SUBJECT_DID" "$NAME" "$JTI" "$OUTPUT"
}

generate_vc_file \
  "${SCRIPT_DIR}/deployment/assets/participant-1/issuer_private.pem" \
  "$P1_ISSUER_DID" "$P1_DID" "Participant 1" "urn:uuid:75da308a-ea17-434c-8618-e1aeb0c6fad1" \
  "${SCRIPT_DIR}/deployment/assets/credentials/participant-1/membership-credential.json"
echo "  Created deployment/assets/credentials/participant-1/membership-credential.json"

generate_vc_file \
  "${SCRIPT_DIR}/deployment/assets/participant-2/issuer_private.pem" \
  "$P2_ISSUER_DID" "$P2_DID" "Participant 2" "urn:uuid:85da308a-ea17-434c-8618-e1aeb0c6fad2" \
  "${SCRIPT_DIR}/deployment/assets/credentials/participant-2/membership-credential.json"
echo "  Created deployment/assets/credentials/participant-2/membership-credential.json"

echo ""
echo "=== Done ==="
echo "All keys and credentials generated. You can now:"
echo "  ./gradlew dockerize    # rebuild images with new public key"
echo "  docker compose up -d   # start services"
echo "  ./deployment/seed.sh   # seed identity data"
