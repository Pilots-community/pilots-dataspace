# Distributed Multi-Machine Deployment

Run EDC connectors on separate machines so they communicate over the network instead of a shared Docker network. Uses DCP (Decentralized Claims Protocol) for identity with did:web DIDs, IdentityHub, and Verifiable Credentials.

## Architecture

Each machine runs a full EDC stack using the same `docker-compose.yml` and port layout. Either machine can act as provider or consumer toward the other.

```
Machine A                                Machine B
+-------------------------------+        +-------------------------------+
| docker-compose.yml            |        | docker-compose.yml            |
|                               |        |                               |
| provider-identityhub   7090+  |        | provider-identityhub   7090+  |
| consumer-identityhub   7080+  |        | consumer-identityhub   7080+  |
|                               |        |                               |
| provider-controlplane  18181  | <----> | provider-controlplane  18181  |
|   mgmt:19193 DSP:19194       |        |   mgmt:19193 DSP:19194       |
|                               |        |                               |
| consumer-controlplane  28181  | <----> | consumer-controlplane  28181  |
|   mgmt:29193 DSP:29194       |        |   mgmt:29193 DSP:29194       |
|                               |        |                               |
| provider-dataplane     38181  | <----> | provider-dataplane     38181  |
|   public:38185               |        |   public:38185               |
|                               |        |                               |
| did-server             9876   |        | did-server             9876   |
| vault                  8200   |        | vault                  8200   |
| postgres              15432   |        | postgres              15432   |
+-------------------------------+        +-------------------------------+
```

Both machines run identical services on identical ports. No port conflicts since they're on different hosts.

## How `MY_PUBLIC_HOST` Works

EDC connectors exchange callback URLs during negotiation and transfer. In the single-machine `docker-compose.yml` (project root), these URLs use Docker service names (e.g. `http://provider-controlplane:19194`). That only works when both connectors share the same Docker network.

In a distributed setup, the remote machine can't resolve Docker service names. `MY_PUBLIC_HOST` is the IP or hostname that **the other machine** will use to reach **this machine**. It gets injected into:

- **DID identifiers**: `did:web:<MY_PUBLIC_HOST>%3A7093` (provider), `did:web:<MY_PUBLIC_HOST>%3A7083` (consumer)
- **DSP callback URLs**: `http://<MY_PUBLIC_HOST>:19194/protocol`
- **IdentityHub hostname**: so DID documents are served with the correct Host header
- **STS key aliases**: so the embedded STS uses the correct key pairs
- **Trusted issuer DID**: `did:web:<MY_PUBLIC_HOST>%3A9876`
- **Data plane public URL**: `http://<MY_PUBLIC_HOST>:38185/public`

**You must set `MY_PUBLIC_HOST` to an address that the remote machine's Docker containers can connect to.** `localhost` will NOT work -- inside a container, `localhost` refers to the container itself.

## Prerequisites

- Docker and Docker Compose
- Docker images built (`./gradlew dockerize` in the project root) -- needs `controlplane`, `dataplane`, and `identityhub` images
- Python 3 with the `cryptography` library (for VC generation in seed.sh)
- Issuer private key at `deployment/assets/issuer_private.pem`
- Both machines must be able to reach each other on the required ports (see [Ports That Must Be Reachable](#ports-that-must-be-reachable))

## Choosing `MY_PUBLIC_HOST` for Your Network Setup

### Same LAN / Same Network

If both machines are on the same local network, use each machine's LAN IP address.

```bash
# Linux
hostname -I | awk '{print $1}'

# macOS
ipconfig getifaddr en0
```

### Different Networks (not directly routable)

#### Tailscale (recommended)

[Tailscale](https://tailscale.com/) creates a private WireGuard mesh network. Each machine gets a stable IP (e.g. `100.64.x.x`) that works across any network.

1. Install Tailscale on both machines: https://tailscale.com/download
2. Run `tailscale up` on each
3. Get each machine's Tailscale IP: `tailscale ip -4`

All ports are automatically reachable between machines with no firewall configuration needed.

#### Other Options

Any VPN, WireGuard tunnel, or cloud VM with a public IP works. Use the routable IP as `MY_PUBLIC_HOST`. Make sure the required ports are open.

### Single-Machine Testing (no Tailscale)

To test on one machine without Tailscale, use the Docker bridge gateway IP:

```bash
# Find the Docker bridge gateway IP (usually 172.17.0.1)
ip addr show docker0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1
```

On macOS/Windows with Docker Desktop, use `host.docker.internal` instead.

## Quick Start

1. Start the services:
   ```bash
   cd deployment/distributed
   MY_PUBLIC_HOST=<your-ip> docker compose up -d
   ```

2. Wait for all containers to be healthy:
   ```bash
   docker ps
   ```

3. Run the seed script to create participant identities and credentials:
   ```bash
   MY_PUBLIC_HOST=<your-ip> ./seed.sh
   ```

4. Repeat on the second machine with its own `MY_PUBLIC_HOST`.

## End-to-End Example

In this example, Machine A is the **provider** (owns the data) and Machine B is the **consumer** (requests data). Replace `<HOST>` with Machine A's `MY_PUBLIC_HOST` value and `<PROVIDER_DID>` with `did:web:<HOST>%3A7093`.

### On Machine A: Set Up the Data (Steps 1-3)

#### 1. Create an Asset

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

#### 2. Create a Policy Definition

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

#### 3. Create a Contract Definition

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

### On Machine B: Discover, Negotiate, and Fetch (Steps 4-7)

#### 4. Request the Catalog from Machine A

```bash
curl -X POST http://localhost:29193/management/v3/catalog/request \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@type": "CatalogRequest",
    "counterPartyAddress": "http://<HOST>:19194/protocol",
    "counterPartyId": "<PROVIDER_DID>",
    "protocol": "dataspace-protocol-http"
  }'
```

In the response, find `dcat:dataset` -> `odrl:hasPolicy` -> `@id`. That's the **offer ID**.

#### 5. Negotiate a Contract

Replace `<OFFER_ID>` with the offer ID from step 4:

```bash
curl -X POST http://localhost:29193/management/v3/contractnegotiations \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/", "odrl": "http://www.w3.org/ns/odrl/2/" },
    "@type": "ContractRequest",
    "counterPartyAddress": "http://<HOST>:19194/protocol",
    "counterPartyId": "<PROVIDER_DID>",
    "protocol": "dataspace-protocol-http",
    "policy": {
      "@type": "odrl:Offer",
      "@id": "<OFFER_ID>",
      "odrl:target": { "@id": "sample-asset-1" },
      "odrl:assigner": { "@id": "<PROVIDER_DID>" },
      "odrl:permission": [], "odrl:prohibition": [], "odrl:obligation": []
    }
  }'
```

Poll until `state` is `FINALIZED`:

```bash
curl http://localhost:29193/management/v3/contractnegotiations/<NEGOTIATION_ID> \
  -H "x-api-key: password"
```

Copy the `contractAgreementId` from the response.

#### 6. Initiate a Data Transfer

```bash
curl -X POST http://localhost:29193/management/v3/transferprocesses \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "http://<HOST>:19194/protocol",
    "protocol": "dataspace-protocol-http",
    "contractId": "<AGREEMENT_ID>",
    "assetId": "sample-asset-1",
    "transferType": "HttpData-PULL"
  }'
```

Poll until `state` is `STARTED`:

```bash
curl http://localhost:29193/management/v3/transferprocesses/<TRANSFER_ID> \
  -H "x-api-key: password"
```

#### 7. Fetch Data via EDR

Retrieve the Endpoint Data Reference:

```bash
curl http://localhost:29193/management/v3/edrs/<TRANSFER_ID>/dataaddress \
  -H "x-api-key: password"
```

The response contains an `endpoint` URL (using Machine A's public IP) and an `authorization` token. Fetch the data:

```bash
curl <ENDPOINT_URL> \
  -H "Authorization: Bearer <TOKEN>"
```

Expected response:

```json
{
  "message": "Data transfer successful via EDC data plane",
  "jti": "c90bca94-7f3d-4aae-8454-be1073677284"
}
```

## Distributing Docker Images

If the second machine doesn't have the source code to build images, transfer them:

```bash
# On the build machine
docker save controlplane:latest dataplane:latest identityhub:latest | gzip > edc-images.tar.gz

# Copy to the other machine
scp edc-images.tar.gz user@machine-b:~/

# On the other machine
docker load < edc-images.tar.gz
```

## Ports That Must Be Reachable

The remote machine needs to reach these ports:

| Port | Service | Why |
|------|---------|-----|
| 7081 | Consumer IdentityHub Credentials API | VP/VC presentation requests |
| 7083 | Consumer IdentityHub DID endpoint | DID document resolution |
| 7091 | Provider IdentityHub Credentials API | VP/VC presentation requests |
| 7093 | Provider IdentityHub DID endpoint | DID document resolution |
| 9876 | DID Server (nginx) | Issuer DID document resolution |
| 19194 | Provider CP DSP | Catalog requests, negotiation callbacks |
| 29194 | Consumer CP DSP | Negotiation callbacks |
| 38185 | Data Plane public | Data fetch via EDR token |

Management ports (19193, 29193) only need to be reachable from your local terminal, not from the remote machine.
