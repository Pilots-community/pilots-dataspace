# Tailscale E2E Test (Single-Machine Simulation)

Full E2E dataspace flow using the Tailscale IP on a single machine. Traffic exits the Docker container, routes through the Tailscale interface on the host, and re-enters through the port mapping -- the same network path as a second machine on the Tailscale network.

## Prerequisites

- Distributed stack running: `MY_PUBLIC_HOST=<tailscale-ip> docker compose up -d`
- Seed script run: `MY_PUBLIC_HOST=<tailscale-ip> ./seed.sh`
- Replace `100.113.174.98` below with your Tailscale IP (`tailscale ip -4`)

## Variables

```bash
HOST=100.113.174.98
PROVIDER_DID="did:web:${HOST}%3A7093"
```

## Steps 1-3: Provider Setup (localhost)

### 1. Create Asset

```bash
curl -X POST http://localhost:19193/management/v3/assets \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@id": "sample-asset-1",
    "properties": { "name": "Sample Data Asset", "contenttype": "application/json" },
    "dataAddress": { "type": "HttpData", "baseUrl": "https://jsonplaceholder.typicode.com/todos/1" }
  }'
```

### 2. Create Policy

```bash
curl -X POST http://localhost:19193/management/v3/policydefinitions \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/", "odrl": "http://www.w3.org/ns/odrl/2/" },
    "@id": "open-policy",
    "policy": { "@type": "odrl:Set", "odrl:permission": [], "odrl:prohibition": [], "odrl:obligation": [] }
  }'
```

### 3. Create Contract Definition

```bash
curl -X POST http://localhost:19193/management/v3/contractdefinitions \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@id": "sample-contract-def",
    "accessPolicyId": "open-policy",
    "contractPolicyId": "open-policy",
    "assetsSelector": []
  }'
```

## Steps 4-7: Consumer Flow via Tailscale

The `counterPartyAddress` and `counterPartyId` use the Tailscale IP and DID, so requests route through the host's Tailscale interface. On a second machine, these calls would be identical.

### 4. Request Catalog via Tailscale IP

```bash
curl -X POST http://localhost:29193/management/v3/catalog/request \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@type": "CatalogRequest",
    "counterPartyAddress": "http://100.113.174.98:19194/protocol",
    "counterPartyId": "did:web:100.113.174.98%3A7093",
    "protocol": "dataspace-protocol-http"
  }'
```

Copy the `@id` from `odrl:hasPolicy` -- that's the offer ID.

### 5. Negotiate Contract

```bash
curl -X POST http://localhost:29193/management/v3/contractnegotiations \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/", "odrl": "http://www.w3.org/ns/odrl/2/" },
    "@type": "ContractRequest",
    "counterPartyAddress": "http://100.113.174.98:19194/protocol",
    "counterPartyId": "did:web:100.113.174.98%3A7093",
    "protocol": "dataspace-protocol-http",
    "policy": {
      "@type": "odrl:Offer",
      "@id": "<OFFER_ID>",
      "odrl:target": { "@id": "sample-asset-1" },
      "odrl:assigner": { "@id": "did:web:100.113.174.98%3A7093" },
      "odrl:permission": [], "odrl:prohibition": [], "odrl:obligation": []
    }
  }'
```

### 5b. Poll Until FINALIZED

```bash
curl http://localhost:29193/management/v3/contractnegotiations/<NEGOTIATION_ID> \
  -H "x-api-key: password"
```

Copy `contractAgreementId` from the response.

### 6. Initiate Transfer

```bash
curl -X POST http://localhost:29193/management/v3/transferprocesses \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "http://100.113.174.98:19194/protocol",
    "protocol": "dataspace-protocol-http",
    "contractId": "<AGREEMENT_ID>",
    "assetId": "sample-asset-1",
    "transferType": "HttpData-PULL"
  }'
```

### 6b. Poll Until STARTED

```bash
curl http://localhost:29193/management/v3/transferprocesses/<TRANSFER_ID> \
  -H "x-api-key: password"
```

### 7a. Get EDR Token

```bash
curl http://localhost:29193/management/v3/edrs/<TRANSFER_ID>/dataaddress \
  -H "x-api-key: password"
```

The `endpoint` is `http://100.113.174.98:38185/public` -- the data plane's public URL uses the Tailscale IP.

### 7b. Fetch Data via Tailscale IP

```bash
curl http://100.113.174.98:38185/public \
  -H "Authorization: Bearer <TOKEN>"
```

Expected response:

```json
{
  "message": "Data transfer successful via EDC data plane",
  "jti": "c90bca94-7f3d-4aae-8454-be1073677284"
}
```

## What's Different from a Real Two-Machine Setup

Nothing. The network path is identical -- traffic exits the container, hits the host's Tailscale interface, and re-enters through Docker's port mapping. A second machine on the same Tailscale network would use the exact same `counterPartyAddress` and `endpoint` URLs.
