#!/bin/bash
set -euo pipefail

# Generate all key pairs needed by the dataspace runtimes.
# Run this once before building Docker images or starting services.
#
# Generated files:
#   config/certs/private-key.pem   — Data plane token signing (EC P-256)
#   config/certs/public-key.pem    — Data plane token verification
#   deployment/assets/issuer_private.pem — VC issuer signing key (EC P-256)
#   deployment/assets/issuer_public.pem  — VC issuer public key
#   deployment/assets/issuer/did.json    — Issuer DID document (updated with public key)
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

echo ""
echo "=== Generating VC Issuer Keys ==="
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
echo "=== Updating Issuer DID Document ==="

"$PYTHON" -c "
from cryptography.hazmat.primitives import serialization
import base64, json, sys

with open(sys.argv[1], 'rb') as f:
    pk = serialization.load_pem_private_key(f.read(), password=None)

pub = pk.public_key()
nums = pub.public_numbers()

def b64e(n, length):
    return base64.urlsafe_b64encode(n.to_bytes(length, 'big')).rstrip(b'=').decode()

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
    'id': 'did:web:did-server%3A9876',
    'verificationMethod': [{
        'id': 'did:web:did-server%3A9876#issuer-key-1',
        'type': 'JsonWebKey2020',
        'controller': 'did:web:did-server%3A9876',
        'publicKeyJwk': jwk
    }],
    'authentication': ['did:web:did-server%3A9876#issuer-key-1'],
    'assertionMethod': ['did:web:did-server%3A9876#issuer-key-1']
}

with open(sys.argv[2], 'w') as f:
    json.dump(did_doc, f, indent=2)
    f.write('\n')

print(f'  Updated {sys.argv[2]}')
" "${SCRIPT_DIR}/deployment/assets/issuer_private.pem" \
  "${SCRIPT_DIR}/deployment/assets/issuer/did.json"

echo ""
echo "=== Generating Pre-signed VCs ==="

ISSUER_DID="did:web:did-server%3A9876"
PROVIDER_DID="did:web:provider-identityhub%3A7093"
CONSUMER_DID="did:web:consumer-identityhub%3A7083"

generate_vc_file() {
  local SUBJECT_DID="$1"
  local NAME="$2"
  local JTI="$3"
  local OUTPUT="$4"

  mkdir -p "$(dirname "$OUTPUT")"

  "$PYTHON" -c "
import json, base64, time, sys
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

with open(sys.argv[1], 'rb') as f:
    pk = serialization.load_pem_private_key(f.read(), password=None)

def b64e(d): return base64.urlsafe_b64encode(d).rstrip(b'=').decode()

issuer_did = sys.argv[5]
hdr = {'alg':'ES256','kid': issuer_did + '#issuer-key-1','typ':'JWT'}
now = int(time.time())
payload = {
    'iss': issuer_did, 'sub': sys.argv[2],
    'iat': now, 'exp': now + 10*365*24*3600, 'jti': sys.argv[4],
    'vc': {
        '@context': ['https://www.w3.org/2018/credentials/v1','https://w3id.org/security/suites/jws-2020/v1','https://www.w3.org/ns/credentials/examples/v1'],
        'id': sys.argv[4],
        'type': ['VerifiableCredential','MembershipCredential'],
        'issuer': issuer_did,
        'issuanceDate': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(now)),
        'expirationDate': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(now + 10*365*24*3600)),
        'credentialSubject': {'id': sys.argv[2], 'memberOf': 'dataspace-pilots', 'name': sys.argv[3], 'status': 'Active Member'}
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
" "${SCRIPT_DIR}/deployment/assets/issuer_private.pem" \
    "$SUBJECT_DID" "$NAME" "$JTI" "$ISSUER_DID" "$OUTPUT"
}

generate_vc_file "$PROVIDER_DID" "Provider" "urn:uuid:75da308a-ea17-434c-8618-e1aeb0c6fad1" \
  "${SCRIPT_DIR}/deployment/assets/credentials/provider/membership-credential.json"
echo "  Created deployment/assets/credentials/provider/membership-credential.json"

generate_vc_file "$CONSUMER_DID" "Consumer" "urn:uuid:85da308a-ea17-434c-8618-e1aeb0c6fad2" \
  "${SCRIPT_DIR}/deployment/assets/credentials/consumer/membership-credential.json"
echo "  Created deployment/assets/credentials/consumer/membership-credential.json"

echo ""
echo "=== Done ==="
echo "All keys and credentials generated. You can now:"
echo "  ./gradlew dockerize    # rebuild images with new public key"
echo "  docker compose up -d   # start services"
echo "  ./deployment/seed.sh   # seed identity data"
