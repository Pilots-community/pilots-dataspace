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
CONSUMER_DID="did:web:${HOST}%3A7083"
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

## Steps 4-7: Consumer Pull Transfer via Tailscale

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

Expected response (the sample asset proxies jsonplaceholder):

```json
{"userId":1,"id":1,"title":"delectus aut autem","completed":false}
```

## Steps 8-11: Push Transfer and Reverse Direction

### 8. Push Transfer (HttpData-PUSH)

Reuse the same contract agreement from step 5. The provider data plane pushes data directly to the http-receiver:

```bash
curl -X POST http://localhost:29193/management/v3/transferprocesses \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "http://100.113.174.98:19194/protocol",
    "counterPartyId": "did:web:100.113.174.98%3A7093",
    "protocol": "dataspace-protocol-http",
    "contractId": "<AGREEMENT_ID>",
    "assetId": "sample-asset-1",
    "transferType": "HttpData-PUSH",
    "dataDestination": {
      "type": "HttpData",
      "baseUrl": "http://100.113.174.98:4000/"
    }
  }'
```

Poll until `COMPLETED`:

```bash
curl http://localhost:29193/management/v3/transferprocesses/<TRANSFER_ID> \
  -H "x-api-key: password"
```

Verify data arrived:

```bash
curl http://localhost:4000/
```

### 9. Reverse: Create Asset, Policy, and Contract on Consumer

```bash
curl -X POST http://localhost:29193/management/v3/assets \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@id": "reverse-asset-1",
    "properties": { "name": "Consumer Data Asset", "contenttype": "application/json" },
    "dataAddress": { "type": "HttpData", "baseUrl": "https://jsonplaceholder.typicode.com/todos/2" }
  }'

curl -X POST http://localhost:29193/management/v3/policydefinitions \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/", "odrl": "http://www.w3.org/ns/odrl/2/" },
    "@id": "reverse-open-policy",
    "policy": { "@type": "odrl:Set", "odrl:permission": [], "odrl:prohibition": [], "odrl:obligation": [] }
  }'

curl -X POST http://localhost:29193/management/v3/contractdefinitions \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@id": "reverse-contract-def",
    "accessPolicyId": "reverse-open-policy",
    "contractPolicyId": "reverse-open-policy",
    "assetsSelector": []
  }'
```

### 10. Reverse: Provider Requests Consumer's Catalog and Negotiates

```bash
curl -X POST http://localhost:19193/management/v3/catalog/request \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@type": "CatalogRequest",
    "counterPartyAddress": "http://100.113.174.98:29194/protocol",
    "counterPartyId": "did:web:100.113.174.98%3A7083",
    "protocol": "dataspace-protocol-http"
  }'
```

Copy the offer ID for `reverse-asset-1`. Negotiate using the provider management API (port 19193). The `assigner` is the consumer's DID:

```bash
curl -X POST http://localhost:19193/management/v3/contractnegotiations \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/", "odrl": "http://www.w3.org/ns/odrl/2/" },
    "@type": "ContractRequest",
    "counterPartyAddress": "http://100.113.174.98:29194/protocol",
    "counterPartyId": "did:web:100.113.174.98%3A7083",
    "protocol": "dataspace-protocol-http",
    "policy": {
      "@type": "odrl:Offer",
      "@id": "<OFFER_ID>",
      "odrl:target": { "@id": "reverse-asset-1" },
      "odrl:assigner": { "@id": "did:web:100.113.174.98%3A7083" },
      "odrl:permission": [], "odrl:prohibition": [], "odrl:obligation": []
    }
  }'
```

### 10b. Poll Until FINALIZED

```bash
curl http://localhost:19193/management/v3/contractnegotiations/<NEGOTIATION_ID> \
  -H "x-api-key: password"
```

Copy `contractAgreementId` from the response.

### 11a. Reverse: Provider Pulls Data via Consumer Data Plane

```bash
curl -X POST http://localhost:19193/management/v3/transferprocesses \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "http://100.113.174.98:29194/protocol",
    "protocol": "dataspace-protocol-http",
    "contractId": "<AGREEMENT_ID>",
    "assetId": "reverse-asset-1",
    "transferType": "HttpData-PULL"
  }'
```

### 11b. Poll Until STARTED

```bash
curl http://localhost:19193/management/v3/transferprocesses/<TRANSFER_ID> \
  -H "x-api-key: password"
```

### 11c. Get EDR and Fetch Data

```bash
curl http://localhost:19193/management/v3/edrs/<TRANSFER_ID>/dataaddress \
  -H "x-api-key: password"
```

The `endpoint` is `http://100.113.174.98:48185/public` -- the **consumer** data plane's public URL.

```bash
curl http://100.113.174.98:48185/public \
  -H "Authorization: Bearer <TOKEN>"
```

Expected response (confirms bidirectional data sharing works):

```json
{"userId":1,"id":2,"title":"quis ut nam facilis et officia qui","completed":false}
```

## What's Different from a Real Two-Machine Setup

Nothing. The network path is identical -- traffic exits the container, hits the host's Tailscale interface, and re-enters through Docker's port mapping. A second machine on the same Tailscale network would use the exact same `counterPartyAddress` and `endpoint` URLs.
