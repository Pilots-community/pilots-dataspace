# Tailscale Multi-Machine Setup

Step-by-step guide to run the dataspace across two machines using [Tailscale](https://tailscale.com/) as the network layer.

## Overview

Each machine runs the full EDC stack (provider + consumer + data plane). Tailscale creates a WireGuard mesh so the machines can reach each other without firewall configuration or port forwarding. All traffic is encrypted end-to-end by WireGuard, so HTTP is safe for dev use.

```
Machine A (100.x.x.x)                    Machine B (100.x.x.x)
+----------------------------+            +----------------------------+
| provider-controlplane      |            | provider-controlplane      |
|   DSP: 19194               | <──────>   |   DSP: 19194               |
| consumer-controlplane      |  Tailscale | consumer-controlplane      |
|   DSP: 29194               | <──────>   |   DSP: 29194               |
| provider-dataplane         |  WireGuard | provider-dataplane         |
|   public: 38185            | <──────>   |   public: 38185            |
+----------------------------+            +----------------------------+
```

## Prerequisites

- Docker and Docker Compose
- Docker images built (`./gradlew dockerize` from project root)
- Token signing keys generated (see root [README](../../README.md#generate-token-signing-keys))

## Setup (per machine)

### 1. Install Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

### 2. Connect to your Tailscale network

```bash
sudo tailscale up
```

Follow the authentication link to log in. Both machines must be on the same Tailscale network (same account or shared).

### 3. Get your Tailscale IP

```bash
tailscale ip -4
```

This returns an IP like `100.113.174.98`.

### 4. Configure the environment

```bash
cd deployment/distributed
cp .env.example .env
```

Edit `.env` and set `MY_PUBLIC_URL` to **this machine's** Tailscale IP:

```properties
MY_PUBLIC_URL=http://100.113.174.98
```

### 5. Start the services

```bash
docker compose up -d
```

### 6. Verify health

```bash
curl http://localhost:18181/api/check/health   # provider CP
curl http://localhost:28181/api/check/health   # consumer CP
curl http://localhost:38181/api/check/health   # data plane
```

### 7. Repeat on the second machine

Install Tailscale, set its own Tailscale IP in `.env`, and start the services.

## Transferring Docker Images

If the second machine doesn't have the source code:

```bash
# On the build machine
docker save controlplane:latest | gzip > controlplane.tar.gz
docker save dataplane:latest | gzip > dataplane.tar.gz

# Copy to the other machine
scp controlplane.tar.gz dataplane.tar.gz user@<tailscale-ip>:~/

# On the other machine
docker load < controlplane.tar.gz
docker load < dataplane.tar.gz
```

## E2E Test Across Machines

In this example:
- **Machine A** (`100.113.174.98`) is the provider
- **Machine B** (`100.64.0.42`) is the consumer

### On Machine A: Set up provider data (steps 1-3)

```bash
# 1. Create asset
curl -X POST http://localhost:19193/management/v3/assets \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@id": "sample-asset-1",
    "properties": { "name": "Sample Data Asset", "contenttype": "application/json" },
    "dataAddress": { "type": "HttpData", "baseUrl": "https://jsonplaceholder.typicode.com/todos/1" }
  }'

# 2. Create policy
curl -X POST http://localhost:19193/management/v3/policydefinitions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/", "odrl": "http://www.w3.org/ns/odrl/2/" },
    "@id": "open-policy",
    "policy": {
      "@context": "http://www.w3.org/ns/odrl.jsonld",
      "@type": "Set",
      "permission": [], "prohibition": [], "obligation": []
    }
  }'

# 3. Create contract definition
curl -X POST http://localhost:19193/management/v3/contractdefinitions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@id": "sample-contract-def",
    "accessPolicyId": "open-policy",
    "contractPolicyId": "open-policy",
    "assetsSelector": []
  }'
```

### On Machine B: Discover, negotiate, and fetch (steps 4-7)

Replace `100.113.174.98` with Machine A's actual Tailscale IP.

```bash
# 4. Request catalog from Machine A's provider
curl -X POST http://localhost:29193/management/v3/catalog/request \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "http://100.113.174.98:19194/protocol",
    "protocol": "dataspace-protocol-http"
  }'
```

Copy the `@id` from `odrl:hasPolicy` in the response — this is the offer ID.

```bash
# 5. Negotiate contract
curl -X POST http://localhost:29193/management/v3/contractnegotiations \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "http://100.113.174.98:19194/protocol",
    "protocol": "dataspace-protocol-http",
    "policy": {
      "@context": "http://www.w3.org/ns/odrl.jsonld",
      "@id": "<OFFER_ID>",
      "@type": "Offer",
      "assigner": "provider",
      "target": "sample-asset-1",
      "permission": [], "prohibition": [], "obligation": []
    }
  }'

# 5b. Poll until FINALIZED
curl http://localhost:29193/management/v3/contractnegotiations/<NEGOTIATION_ID> \
  -H "X-Api-Key: password"
```

Copy the `contractAgreementId` from the finalized response.

```bash
# 6. Initiate transfer
curl -X POST http://localhost:29193/management/v3/transferprocesses \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "http://100.113.174.98:19194/protocol",
    "protocol": "dataspace-protocol-http",
    "contractId": "<AGREEMENT_ID>",
    "assetId": "sample-asset-1",
    "transferType": "HttpData-PULL"
  }'

# 6b. Poll until STARTED
curl http://localhost:29193/management/v3/transferprocesses/<TRANSFER_ID> \
  -H "X-Api-Key: password"
```

```bash
# 7a. Get EDR token
curl http://localhost:29193/management/v3/edrs/<TRANSFER_ID>/dataaddress \
  -H "X-Api-Key: password"

# 7b. Fetch data (endpoint will contain Machine A's Tailscale IP)
curl <ENDPOINT_URL> \
  -H "Authorization: Bearer <TOKEN>"
```

## Single-Machine Testing

You can test this setup on one machine. Traffic goes out through the Tailscale interface and back, exercising the same network path as a real multi-machine setup.

```bash
tailscale ip -4                    # e.g. 100.113.174.98
# Set MY_PUBLIC_URL to the Tailscale IP in .env, then:
docker compose up -d
# Use the Tailscale IP as counterPartyAddress in catalog/negotiation requests
```

## Security Notes

- All traffic between machines is encrypted by WireGuard (Tailscale). HTTP is fine for dev.
- `iam-mock` is in use — no real identity verification between connectors.
- Management ports (19193, 29193) are accessible to anyone on your Tailscale network.
- Only authorize trusted devices on your Tailscale network.
- This setup is for **development and testing only**.
