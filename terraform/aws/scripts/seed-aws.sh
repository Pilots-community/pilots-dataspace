#!/usr/bin/env bash
set -euo pipefail

# Bootstraps identity data on the deployed connector:
#   - generates a Membership VC signed by the issuer key
#   - creates the participant context in IdentityHub
#   - activates the context and publishes the connector DID
#   - stores the STS client secret in the controlplane vault
#   - stores the Membership VC in IdentityHub
#   - registers the local issuer as trusted
#
# Runs from the operator workstation. Hits the ALB on port-specific listeners
# (operator's IP must be in mgmt_cidrs).
#
# Prerequisites:
#   - terraform apply has succeeded
#   - db-seeder + did.json seeder have run (./scripts/run-db-seeder.sh and the
#     seeder_run_command output)
#   - Repo-root ./generate-keys.sh has been run (issuer key available locally)
#
# Idempotent — POST → 409 falls back to PUT for secrets, and trusted-issuer
# accepts 409 as already-registered.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${TF_DIR}/../.." && pwd)"

cd "${TF_DIR}"
DOMAIN=$(terraform output -raw service_urls | sed -n 's/.*dashboard *= *"https:\/\/\([^/]*\).*/\1/p' | head -1)
if [[ -z "${DOMAIN}" ]]; then
  # Fallback: read raw value of dashboard URL via JSON.
  DOMAIN=$(terraform output -json service_urls | python3 -c "import json,sys,urllib.parse as u; print(u.urlparse(json.load(sys.stdin)['dashboard']).hostname)")
fi
echo "Domain: ${DOMAIN}"

SUPERUSER_KEY="c3VwZXItdXNlcg==.superuser-token"

DID="did:web:${DOMAIN}%3A7093"
ISSUER_DID="did:web:${DOMAIN}%3A9876"
DID_B64=$(printf '%s' "${DID}" | base64)

IH_IDENTITY="https://${DOMAIN}:7092/api/identity"
MGMT="https://${DOMAIN}:19193/management"
DSP="https://${DOMAIN}:19194/protocol"
CREDENTIAL_SVC="https://${DOMAIN}:7091/api/credentials/v1/participants/${DID_B64}"

ISSUER_KEY="${REPO_ROOT}/deployment/assets/issuer_private.pem"
if [[ ! -f "${ISSUER_KEY}" ]]; then
  echo "ERROR: ${ISSUER_KEY} not found. Run ./generate-keys.sh from the repo root." >&2
  exit 1
fi

echo "=== 1. Reachability check ==="
curl -fsS --max-time 5 "https://${DOMAIN}/" -o /dev/null \
  || { echo "ERROR: dashboard unreachable. Check mgmt_cidrs and NS delegation." >&2; exit 1; }
echo "  OK"

echo
echo "=== 2. Generating Membership VC ==="
generate_vc() {
  local subject_did="$1" name="$2" jti="$3"
  python3 - "${ISSUER_KEY}" "${subject_did}" "${name}" "${jti}" <<'PY'
import json, base64, time, sys
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

with open(sys.argv[1], 'rb') as f:
    pk = serialization.load_pem_private_key(f.read(), password=None)

import os
issuer_did = os.environ['ISSUER_DID']
subject = sys.argv[2]
name = sys.argv[3]
jti = sys.argv[4]

def b64e(d): return base64.urlsafe_b64encode(d).rstrip(b'=').decode()
hdr = {'alg':'ES256','kid':f'{issuer_did}#issuer-key-1','typ':'JWT'}
now = int(time.time())
payload = {
    'iss': issuer_did, 'sub': subject,
    'iat': now, 'exp': now + 10*365*24*3600, 'jti': jti,
    'vc': {
        '@context': ['https://www.w3.org/2018/credentials/v1','https://w3id.org/security/suites/jws-2020/v1','https://www.w3.org/ns/credentials/examples/v1'],
        'id': jti,
        'type': ['VerifiableCredential','MembershipCredential'],
        'issuer': issuer_did,
        'issuanceDate': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(now)),
        'expirationDate': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(now + 10*365*24*3600)),
        'credentialSubject': {'id': subject, 'memberOf': 'dataspace-pilots', 'name': name, 'status': 'Active Member'}
    }
}
h = b64e(json.dumps(hdr, separators=(',', ':')).encode())
p = b64e(json.dumps(payload, separators=(',', ':')).encode())
sig = pk.sign(f'{h}.{p}'.encode(), ec.ECDSA(hashes.SHA256()))
r, s = decode_dss_signature(sig)
print(f"{h}.{p}.{b64e(r.to_bytes(32,'big')+s.to_bytes(32,'big'))}")
PY
}

export ISSUER_DID
VC_JWT=$(generate_vc "${DID}" "Connector" "urn:uuid:$(python3 -c 'import uuid;print(uuid.uuid4())')")
echo "  VC generated for ${DID}"

echo
echo "=== 3. Creating participant context in IdentityHub ==="
PARTICIPANT_BODY=$(cat <<JSON
{
  "participantContextId": "${DID}",
  "did": "${DID}",
  "active": true,
  "key": {
    "keyId": "${DID}#key-1",
    "privateKeyAlias": "${DID}-alias",
    "keyGeneratorParams": { "algorithm": "EdDSA", "curve": "Ed25519" }
  },
  "serviceEndpoints": [
    { "type": "CredentialService", "serviceEndpoint": "${CREDENTIAL_SVC}", "id": "connector-credentialservice-1" },
    { "type": "ProtocolEndpoint",  "serviceEndpoint": "${DSP}",            "id": "connector-dsp" }
  ],
  "roles": []
}
JSON
)

RESULT=$(curl -sS -w "\n%{http_code}" -X POST "${IH_IDENTITY}/v1alpha/participants" \
  -H "Content-Type: application/json" -H "x-api-key: ${SUPERUSER_KEY}" \
  -d "${PARTICIPANT_BODY}")
HTTP_CODE=$(echo "${RESULT}" | tail -1)
BODY=$(echo "${RESULT}" | sed '$d')
echo "  HTTP ${HTTP_CODE}: ${BODY:-<no body>}"

CLIENT_SECRET=""
case "${HTTP_CODE}" in
  200|201|204) CLIENT_SECRET=$(echo "${BODY}" | jq -r '.clientSecret // empty' 2>/dev/null || true) ;;
  409)         echo "  Already exists — STS secret unchanged from prior seed run." ;;
  *)           echo "  ERROR creating participant context" >&2; exit 1 ;;
esac

echo
echo "=== 4. Activating participant context ==="
curl -sS -X POST "${IH_IDENTITY}/v1alpha/participants/${DID_B64}/state?isActive=true" \
  -H "x-api-key: ${SUPERUSER_KEY}" -w "  HTTP %{http_code}\n"

echo
echo "=== 5. Publishing DID document ==="
curl -sS -X POST "${IH_IDENTITY}/v1alpha/participants/${DID_B64}/dids/publish" \
  -H "Content-Type: application/json" -H "x-api-key: ${SUPERUSER_KEY}" \
  -d "{\"did\":\"${DID}\"}" -w "  HTTP %{http_code}\n"

if [[ -n "${CLIENT_SECRET}" ]]; then
  echo
  echo "=== 6. Storing STS client secret in controlplane vault ==="
  SECRET_BODY=$(cat <<JSON
{
  "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
  "@type": "Secret",
  "@id": "${DID}-sts-client-secret",
  "value": "${CLIENT_SECRET}"
}
JSON
)
  STATUS=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "${MGMT}/v3/secrets" \
    -H "Content-Type: application/json" -H "x-api-key: password" \
    -d "${SECRET_BODY}")
  if [[ "${STATUS}" == "409" ]]; then
    STATUS=$(curl -sS -o /dev/null -w "%{http_code}" -X PUT "${MGMT}/v3/secrets" \
      -H "Content-Type: application/json" -H "x-api-key: password" \
      -d "${SECRET_BODY}")
  fi
  echo "  HTTP ${STATUS}"
fi

echo
echo "=== 7. Storing Membership VC in IdentityHub ==="
VC_MANIFEST=$(python3 - "${VC_JWT}" "${DID}" <<'PY'
import base64, json, sys
jwt = sys.argv[1]; participant_did = sys.argv[2]
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
print(json.dumps({
    'id': 'membership-credential',
    'participantContextId': participant_did,
    'verifiableCredentialContainer': {'rawVc': jwt, 'format': 'VC1_0_JWT', 'credential': credential}
}))
PY
)
curl -sS -X POST "${IH_IDENTITY}/v1alpha/participants/${DID_B64}/credentials" \
  -H "Content-Type: application/json" -H "x-api-key: ${SUPERUSER_KEY}" \
  -d "${VC_MANIFEST}" -w "  HTTP %{http_code}\n"

echo
echo "=== 8. Registering local issuer as trusted ==="
TI_BODY=$(cat <<JSON
{"did":"${ISSUER_DID}","name":"Local Issuer","organization":"AWS Deployment","dspEndpoint":"${DSP}","participantDid":"${DID}"}
JSON
)
STATUS=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "${MGMT}/v1/trusted-issuers" \
  -H "Content-Type: application/json" -H "x-api-key: password" \
  -d "${TI_BODY}")
echo "  HTTP ${STATUS} (200/204 = new, 409 = already registered)"

echo
echo "=== Seeding complete ==="
echo "  Connector DID: ${DID}"
echo "  Issuer DID:    ${ISSUER_DID}"
echo "  Dashboard:     https://${DOMAIN}/"
