# Distributed Multi-Machine Deployment

Run EDC connectors on separate machines communicating over a network tunnel (Tailscale, ngrok, or any routable IP).

## Architecture

Each machine runs a full EDC stack using the same `docker-compose.yml` and port layout. Either machine can act as provider or consumer toward the other.

```
Machine A                                Machine B
+-------------------------------+        +-------------------------------+
| docker-compose.yml            |        | docker-compose.yml            |
|                               |        |                               |
| provider-controlplane  18181  | <----> | provider-controlplane  18181  |
|   mgmt:19193 DSP:19194       | tunnel  |   mgmt:19193 DSP:19194       |
|                               |        |                               |
| consumer-controlplane  28181  | <----> | consumer-controlplane  28181  |
|   mgmt:29193 DSP:29194       |        |   mgmt:29193 DSP:29194       |
|                               |        |                               |
| provider-dataplane     38181  | <----> | provider-dataplane     38181  |
|   public:38185               |        |   public:38185               |
+-------------------------------+        +-------------------------------+
```

Both machines run identical services on identical ports. No port conflicts since they're on different hosts. The `-D` JVM flags in the compose file override cross-network properties with `MY_PUBLIC_URL` so the remote machine can reach back.

## Prerequisites

- Docker and Docker Compose
- Docker images built (`./gradlew dockerize` in the project root)
- Token signing keys generated (see root [README.md](../../README.md#generate-token-signing-keys))
- A network tunnel or routable IP between the two machines

## Setting Up a Tunnel

### Tailscale (recommended)

[Tailscale](https://tailscale.com/) creates a private WireGuard mesh network. Each machine gets a stable IP (e.g. `100.64.x.x`).

1. Install Tailscale on both machines
2. Run `tailscale up` on each
3. Note each machine's Tailscale IP: `tailscale ip -4`
4. Use `http://<tailscale-ip>` as `MY_PUBLIC_URL`

All ports are reachable between machines with no extra configuration.

### ngrok

[ngrok](https://ngrok.com/) exposes local ports via public URLs. Since each tunnel gets a different hostname, this requires editing the `-D` flags in the compose file directly.

1. Start a tunnel for each port that must be reachable from the remote machine:
   ```bash
   ngrok http 19194  # provider DSP
   ngrok http 29194  # consumer DSP
   ngrok http 38185  # data plane public
   ```
2. Each tunnel gets a unique URL (e.g. `https://abc123.ngrok.io`). You'll need to replace the `${MY_PUBLIC_URL}:<port>` values in the compose file's `-D` flags with the corresponding ngrok URLs (without port numbers, since ngrok handles routing).

ngrok works for quick tests but Tailscale is simpler for ongoing use.

## Quick Start

1. Copy the env file and set your public URL:
   ```bash
   cd deployment/distributed
   cp .env.example .env
   # Edit .env — set MY_PUBLIC_URL to this machine's tunnel/public address
   ```

2. Start the services:
   ```bash
   docker compose up
   ```

3. Verify health:
   ```bash
   curl http://localhost:18181/api/check/health  # provider CP
   curl http://localhost:28181/api/check/health  # consumer CP
   curl http://localhost:38181/api/check/health  # data plane
   ```

4. Repeat on the second machine with its own `MY_PUBLIC_URL`.

## Distributing Docker Images

If the second machine doesn't have the source code to build images, transfer them:

```bash
# On the build machine
docker save controlplane:latest | gzip > controlplane.tar.gz
docker save dataplane:latest | gzip > dataplane.tar.gz

# Copy to the other machine (scp, rsync, USB, etc.)
scp controlplane.tar.gz dataplane.tar.gz user@machine-b:~/

# On the other machine
docker load < controlplane.tar.gz
docker load < dataplane.tar.gz
```

## Ports That Must Be Reachable

The remote machine needs to reach these ports through the tunnel:

| Port | Service | Why |
|------|---------|-----|
| 19194 | Provider CP DSP | Catalog requests, negotiation callbacks |
| 29194 | Consumer CP DSP | Negotiation callbacks, EDR notifications |
| 38185 | Data Plane public | Data fetch via EDR token |

Management ports (19193, 29193) only need to be reachable from your local terminal, not from the remote machine.

## End-to-End Example Across Two Machines

In this example, Machine A is the **provider** (owns the data) and Machine B is the **consumer** (requests data). Replace `<A_PUBLIC_URL>` with Machine A's tunnel address (e.g. `http://100.64.0.1`).

### On Machine A: Set Up the Data (Steps 1-3)

#### 1. Create an Asset

```bash
curl -X POST http://localhost:19193/management/v3/assets \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@id": "sample-asset-1",
    "properties": {
      "name": "Sample Data Asset",
      "description": "A sample dataset for testing the dataspace",
      "contenttype": "application/json"
    },
    "dataAddress": {
      "type": "HttpData",
      "baseUrl": "https://jsonplaceholder.typicode.com/todos/1"
    }
  }'
```

#### 2. Create a Policy Definition

```bash
curl -X POST http://localhost:19193/management/v3/policydefinitions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": {
      "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
      "odrl": "http://www.w3.org/ns/odrl/2/"
    },
    "@id": "open-policy",
    "policy": {
      "@context": "http://www.w3.org/ns/odrl.jsonld",
      "@type": "Set",
      "permission": [],
      "prohibition": [],
      "obligation": []
    }
  }'
```

#### 3. Create a Contract Definition

```bash
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

### On Machine B: Discover, Negotiate, and Fetch (Steps 4-7)

#### 4. Request the Catalog from Machine A

```bash
curl -X POST http://localhost:29193/management/v3/catalog/request \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "<A_PUBLIC_URL>:19194/protocol",
    "protocol": "dataspace-protocol-http"
  }'
```

In the response, find the `dcat:dataset` entry for `sample-asset-1`. Inside it, `odrl:hasPolicy` contains the offer. Copy the `@id` of that policy — this is the **offer ID** (a Base64-encoded string).

#### 5. Negotiate a Contract

Replace `<OFFER_ID>` with the offer ID from step 4:

```bash
curl -X POST http://localhost:29193/management/v3/contractnegotiations \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "<A_PUBLIC_URL>:19194/protocol",
    "protocol": "dataspace-protocol-http",
    "policy": {
      "@context": "http://www.w3.org/ns/odrl.jsonld",
      "@id": "<OFFER_ID>",
      "@type": "Offer",
      "assigner": "provider",
      "target": "sample-asset-1",
      "permission": [],
      "prohibition": [],
      "obligation": []
    }
  }'
```

Poll until `state` is `FINALIZED`:

```bash
curl http://localhost:29193/management/v3/contractnegotiations/<NEGOTIATION_ID> \
  -H "X-Api-Key: password"
```

Copy the `contractAgreementId` from the response.

#### 6. Initiate a Data Transfer

Replace `<AGREEMENT_ID>` with the contract agreement ID from step 5:

```bash
curl -X POST http://localhost:29193/management/v3/transferprocesses \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "<A_PUBLIC_URL>:19194/protocol",
    "protocol": "dataspace-protocol-http",
    "contractId": "<AGREEMENT_ID>",
    "assetId": "sample-asset-1",
    "transferType": "HttpData-PULL"
  }'
```

Poll until `state` is `STARTED`:

```bash
curl http://localhost:29193/management/v3/transferprocesses/<TRANSFER_ID> \
  -H "X-Api-Key: password"
```

#### 7. Fetch Data via EDR

Retrieve the Endpoint Data Reference:

```bash
curl http://localhost:29193/management/v3/edrs/<TRANSFER_ID>/dataaddress \
  -H "X-Api-Key: password"
```

The response contains an `endpoint` URL and an `authorization` token. In the distributed setup the `endpoint` will already contain Machine A's public URL (since the data plane's `edc.dataplane.api.public.baseurl` was set to `MY_PUBLIC_URL`). Use the token to fetch the data:

```bash
curl <ENDPOINT_URL> \
  -H "Authorization: Bearer <TOKEN>"
```

This returns the data from the asset's backing data source.

## Security Notes

- This setup uses `iam-mock` (no real identity verification) and plain HTTP. It is intended for **development and testing only**.
- Do not expose management ports (19193, 29193) to untrusted networks.
- For production, configure proper IAM (e.g. DAPS/DIM), TLS, and network policies.
