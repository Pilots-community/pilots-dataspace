# Connector Deployment

Deploy a self-contained EDC connector stack to a cloud VM (Azure, AWS, GCP, etc.) or any server with a public IP. Each organization runs its own Control Plane, Data Plane, Identity Hub, and DID server. Connectors communicate over the internet using DCP (Decentralized Claims Protocol) with did:web DIDs and Verifiable Credentials.

## Architecture

Each VM is fully independent — it generates its own keys, signs its own VCs, and serves its own issuer DID document. Trust between connectors is established by registering each other's issuer DIDs via the dashboard or REST API.

```
Organization A (VM: 20.50.100.10)        Organization B (VM: 20.50.100.20)
+-----------------------------+          +-----------------------------+
| docker-compose.yml          |          | docker-compose.yml          |
|                             |          |                             |
| identityhub        7090-96  |          | identityhub        7090-96  |
| controlplane       18181    |          | controlplane       18181    |
|   mgmt:19193 DSP:19194      |  <---->  |   mgmt:19193 DSP:19194      |
| dataplane          38181    |          | dataplane          38181    |
|   public:38185              |          |   public:38185              |
| dashboard          3000     |          | dashboard          3000     |
| http-receiver      4000     |          | http-receiver      4000     |
| did-server         9876     |          | did-server         9876     |
| vault              8200     |          | vault              8200     |
| postgres          15432     |          | postgres          15432     |
+-----------------------------+          +-----------------------------+
```

All VMs use the same ports — no conflicts since they're on different hosts.

## Prerequisites

| Dependency | Version | What it's for | Install |
|-----------|---------|---------------|---------|
| **Docker** | 20.10+ | Runs all services as containers | [docs.docker.com/get-docker](https://docs.docker.com/get-docker/) |
| **Docker Compose** | v2+ | Orchestrates the 8-container stack | Included with Docker; `apt install docker-compose-plugin` |
| **Python 3** | 3.8+ | `seed.sh` uses it for VC signing and JSON processing | `apt install python3` |
| **`cryptography`** | any | EC key operations for VC JWT signing | `pip3 install cryptography` |
| **`jq`** | any | JSON parsing in seed script | `apt install jq` |
| **`curl`** | any | API calls in seed script | `apt install curl` |
| **`openssl`** | 1.1+ | Key generation | `apt install openssl` |
| **JDK** | 17+ | Build only — compiles Java and builds Docker images | `apt install openjdk-17-jdk` |

> VMs that don't build from source can load pre-built Docker images instead (see [Distributing Docker Images](#distributing-docker-images)).

## Quick Start (Cloud VM)

### 1. Provision a VM

Create a VM with a public IP. Recommended minimum: 2 vCPUs, 4 GB RAM.

**Example (Azure CLI):**
```bash
az vm create \
  --resource-group myResourceGroup \
  --name edc-connector \
  --image Ubuntu2204 \
  --size Standard_B2s \
  --admin-username azureuser \
  --generate-ssh-keys
```

### 2. Open firewall ports

Open the required ports in your cloud provider's network security group / firewall.

**Ports that must be reachable from other connectors:**

| Port | Service | Why |
|------|---------|-----|
| 7091 | IdentityHub Credentials API | VP/VC presentation requests |
| 7093 | IdentityHub DID endpoint | Participant DID document resolution |
| 9876 | DID Server (nginx) | Issuer DID document resolution |
| 19194 | Control Plane DSP | Catalog requests, negotiation/transfer callbacks |
| 38185 | Data Plane public | Data fetch via EDR token (pull transfers) |

**Optional — only for your own access:**

| Port | Service | Why |
|------|---------|-----|
| 3000 | Dashboard | Web UI (restrict to your IP) |
| 19193 | Management API | REST API (restrict to your IP) |
| 4000 | http-receiver | Push transfer test destination |

**Example (Azure CLI):**
```bash
az vm open-port --resource-group myResourceGroup --name edc-connector \
  --port 7091,7093,9876,19194,38185,3000 --priority 1000
```

### 3. Install dependencies on the VM

```bash
ssh azureuser@<PUBLIC_IP>

sudo apt update && sudo apt install -y \
  openjdk-17-jdk python3 python3-pip jq curl git docker.io docker-compose-plugin

sudo pip3 install cryptography
sudo usermod -aG docker $USER
newgrp docker
```

### 4. Clone the repo and generate keys

```bash
git clone <repo-url> && cd pilots-dataspace
./generate-keys.sh
```

This creates:
- `config/certs/private-key.pem` and `public-key.pem` (data plane token keys)
- `deployment/assets/issuer_private.pem` and `issuer_public.pem` (VC issuer keys)

### 5. Build Docker images

```bash
./gradlew dockerize
```

This produces three local Docker images: `controlplane:latest`, `dataplane:latest`, `identityhub:latest`.

### 6. Configure environment

```bash
cd deployment/connector
cp .env.example .env
```

Edit `.env` — set `MY_PUBLIC_HOST` to the VM's **public IP or DNS name**:

```bash
MY_PUBLIC_HOST=20.50.100.10
```

`MY_PUBLIC_HOST` is the address other connectors will use to reach this VM. It gets injected into:
- **DID identifiers**: `did:web:<MY_PUBLIC_HOST>%3A7093`
- **DSP callback URLs**: `http://<MY_PUBLIC_HOST>:19194/protocol`
- **Data plane public URL**: `http://<MY_PUBLIC_HOST>:38185/public`
- **Issuer DID document**: `did:web:<MY_PUBLIC_HOST>%3A9876`

### 7. Start the stack

```bash
docker compose up -d
```

Wait for all containers to be healthy:

```bash
docker ps
```

All 8 containers should show `(healthy)`. This typically takes 30-60 seconds.

### 8. Seed identity data

```bash
MY_PUBLIC_HOST=20.50.100.10 ./seed.sh
```

The seed script:
1. Generates a MembershipCredential VC (signed with this VM's issuer key)
2. Creates a participant context in IdentityHub
3. Publishes the participant's DID document
4. Stores the STS client secret in the Control Plane's vault
5. Stores the MembershipCredential in IdentityHub
6. Updates the issuer DID document on the DID server (nginx)
7. Registers this VM's issuer as a trusted issuer in the Control Plane

### 9. Open the dashboard

The dashboard is available at **http://\<PUBLIC_IP\>:3000**. It provides a UI for managing assets, policies, contracts, transfers, and trusted issuers.

Key pages:
- **Trusted Issuers** — add remote connectors' issuer DIDs (with DSP endpoint and participant DID) so your connector trusts their VCs
- **Catalog** — browse remote connectors' catalogs. Trusted issuers with connector details appear as clickable quick-select buttons that prefill the counter party fields

### 10. Share your connector details

After setup, share these three values with other organizations so they can register your connector:

| What | Value | Example |
|------|-------|---------|
| **Issuer DID** | `did:web:<MY_PUBLIC_HOST>%3A9876` | `did:web:20.50.100.10%3A9876` |
| **DSP Endpoint** | `http://<MY_PUBLIC_HOST>:19194/protocol` | `http://20.50.100.10:19194/protocol` |
| **Participant DID** | `did:web:<MY_PUBLIC_HOST>%3A7093` | `did:web:20.50.100.10%3A7093` |

They will register these on their connector via the Trusted Issuers page. You must do the same with their details.

## Connecting Two Connectors

Once both VMs are running and seeded:

### 1. Exchange connector details

Each organization shares their issuer DID, DSP endpoint, and participant DID (see step 10 above).

### 2. Register each other as trusted issuers

On **VM A's** dashboard (or via API), go to **Trusted Issuers** → **Add Issuer** and enter VM B's details:

| Field | Value |
|-------|-------|
| DID | `did:web:20.50.100.20%3A9876` |
| Name | Organization B |
| Organization | Org B |
| DSP Endpoint | `http://20.50.100.20:19194/protocol` |
| Participant DID | `did:web:20.50.100.20%3A7093` |

Do the same on **VM B** with VM A's details.

Via the API:
```bash
curl -X POST http://localhost:19193/management/v1/trusted-issuers \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "did": "did:web:20.50.100.20%3A9876",
    "name": "Organization B",
    "organization": "Org B",
    "dspEndpoint": "http://20.50.100.20:19194/protocol",
    "participantDid": "did:web:20.50.100.20%3A7093"
  }'
```

### 3. Verify connectivity

From each VM, test the other's endpoints:

```bash
# Issuer DID document (should return JSON)
curl http://<OTHER_HOST>:9876/.well-known/did.json

# DSP endpoint (should return a JSON error, not connection refused)
curl http://<OTHER_HOST>:19194/protocol

# Participant DID document
curl http://<OTHER_HOST>:7093/.well-known/did.json
```

### 4. Browse the catalog

Go to the **Catalog** page in the dashboard. The remote connector appears as a clickable button — click it and hit **Fetch Catalog**.

Or via curl:
```bash
curl -X POST http://localhost:19193/management/v3/catalog/request \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@type": "CatalogRequest",
    "counterPartyAddress": "http://<OTHER_HOST>:19194/protocol",
    "counterPartyId": "did:web:<OTHER_HOST>%3A7093",
    "protocol": "dataspace-protocol-http"
  }'
```

## End-to-End Example

VM A (`20.50.100.10`) is the **provider**, VM B (`20.50.100.20`) is the **consumer**.

### On VM A: Create Asset, Policy, and Contract

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

### On VM B: Negotiate and Fetch

> Make sure both VMs have registered each other as trusted issuers first (see [Connecting Two Connectors](#connecting-two-connectors)).

#### 4. Request Catalog

```bash
curl -X POST http://localhost:19193/management/v3/catalog/request \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@type": "CatalogRequest",
    "counterPartyAddress": "http://20.50.100.10:19194/protocol",
    "counterPartyId": "did:web:20.50.100.10%3A7093",
    "protocol": "dataspace-protocol-http"
  }'
```

Find `dcat:dataset` → `odrl:hasPolicy` → `@id` in the response — that's the **offer ID**.

#### 5. Negotiate a Contract

```bash
curl -X POST http://localhost:19193/management/v3/contractnegotiations \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/", "odrl": "http://www.w3.org/ns/odrl/2/" },
    "@type": "ContractRequest",
    "counterPartyAddress": "http://20.50.100.10:19194/protocol",
    "counterPartyId": "did:web:20.50.100.10%3A7093",
    "protocol": "dataspace-protocol-http",
    "policy": {
      "@type": "odrl:Offer",
      "@id": "<OFFER_ID>",
      "odrl:target": { "@id": "sample-asset-1" },
      "odrl:assigner": { "@id": "did:web:20.50.100.10%3A7093" },
      "odrl:permission": [], "odrl:prohibition": [], "odrl:obligation": []
    }
  }'
```

Poll until `state` is `FINALIZED`:

```bash
curl http://localhost:19193/management/v3/contractnegotiations/<NEGOTIATION_ID> \
  -H "x-api-key: password"
```

Copy the `contractAgreementId`.

#### 6. Initiate a Data Transfer (Pull)

```bash
curl -X POST http://localhost:19193/management/v3/transferprocesses \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "http://20.50.100.10:19194/protocol",
    "protocol": "dataspace-protocol-http",
    "contractId": "<AGREEMENT_ID>",
    "assetId": "sample-asset-1",
    "transferType": "HttpData-PULL"
  }'
```

Poll until `state` is `STARTED`:

```bash
curl http://localhost:19193/management/v3/transferprocesses/<TRANSFER_ID> \
  -H "x-api-key: password"
```

#### 7. Fetch Data via EDR

```bash
curl http://localhost:19193/management/v3/edrs/<TRANSFER_ID>/dataaddress \
  -H "x-api-key: password"
```

The response contains an `endpoint` URL and `authorization` token:

```bash
curl <ENDPOINT_URL> \
  -H "Authorization: Bearer <TOKEN>"
```

Expected response:
```json
{"userId":1,"id":1,"title":"delectus aut autem","completed":false}
```

### Push Transfer (HttpData-PUSH)

Reuse the contract agreement from step 5:

```bash
curl -X POST http://localhost:19193/management/v3/transferprocesses \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "http://20.50.100.10:19194/protocol",
    "counterPartyId": "did:web:20.50.100.10%3A7093",
    "protocol": "dataspace-protocol-http",
    "contractId": "<AGREEMENT_ID>",
    "assetId": "sample-asset-1",
    "transferType": "HttpData-PUSH",
    "dataDestination": {
      "type": "HttpData",
      "baseUrl": "http://20.50.100.20:4000/"
    }
  }'
```

Once the transfer reaches `COMPLETED`, verify the data arrived:

```bash
curl http://localhost:4000/
```

## Adding More Connectors

1. Provision and set up the new VM (steps 1-9)
2. On each existing connector's dashboard, go to **Trusted Issuers** and add the new connector's issuer DID, DSP endpoint, and participant DID
3. On the new connector's dashboard, add each existing connector's details the same way

## Networking Notes

### Bidirectional connectivity is required

The DSP protocol requires both connectors to reach each other. Even if you only want to consume data, the provider must reach your connector to verify your identity (DID resolution, VP requests) and send negotiation callbacks. All ports in the table above must be open in both directions.

### Laptops / machines behind NAT

If your machine doesn't have a public IP (e.g. a laptop behind a home router), you have a few options:

- **[Tailscale](https://tailscale.com/)** — creates a private WireGuard mesh. Install on both machines, run `tailscale up`, and use the Tailscale IPs as `MY_PUBLIC_HOST`. Free, no port forwarding needed.
- **Router port forwarding** — forward the required ports to your machine's LAN IP and use your public IP as `MY_PUBLIC_HOST`.
- **Deploy to a cloud VM instead** — even a small VM (e.g. Azure B1s, ~$4/month) avoids all NAT issues.

### Using a DNS name

You can use a DNS name instead of an IP for `MY_PUBLIC_HOST` (e.g. `my-connector.westeurope.cloudapp.azure.com`). The DIDs will use the DNS name (e.g. `did:web:my-connector.westeurope.cloudapp.azure.com%3A7093`).

## Distributing Docker Images

If a VM doesn't have the source code or JDK to build images, transfer pre-built images:

```bash
# On the build machine
docker save controlplane:latest dataplane:latest identityhub:latest | gzip > edc-images.tar.gz

# Copy to the VM
scp edc-images.tar.gz azureuser@20.50.100.10:~/

# On the VM
docker load < edc-images.tar.gz
```

The tarball is typically ~300-400 MB. VMs that load images this way still need:
- The repository files (for config, `seed.sh`, `docker-compose.yml`, `generate-keys.sh`)
- Python 3 + `cryptography` + `jq` + `curl` (for `seed.sh`)
- OpenSSL (for `generate-keys.sh`)

The simplest approach is to clone the repository on every VM. Alternatively, copy just the required files:

```bash
# Minimal set of files needed on a non-build VM
deployment/connector/         # docker-compose.yml, seed.sh, .env.example
deployment/nginx.conf         # nginx config for DID server
deployment/http-receiver/     # push transfer test receiver
config/docker/*-connector.*   # runtime config files
config/certs/                 # generated after running generate-keys.sh
deployment/assets/            # generated after running generate-keys.sh
generate-keys.sh              # key generation script
```

## Resetting a VM

To wipe all state and start fresh:

```bash
cd deployment/connector
docker compose down -v    # stops containers AND deletes volumes (DB data, DID docs)
```

Then re-run from step 7 of the [Quick Start](#7-start-the-stack). Keys don't need to be regenerated unless you want new ones.

## Troubleshooting

### 401 Unauthorized on catalog/negotiation

- Verify the remote connector's issuer DID is registered via the **Trusted Issuers** page
- Verify the remote issuer DID document is accessible: `curl http://<remote-host>:9876/.well-known/did.json`
- Check that `MY_PUBLIC_HOST` is correct and reachable from the remote connector's Docker containers

### DID resolution failures

- Verify the IdentityHub DID endpoint is accessible: `curl http://<host>:7093/.well-known/did.json`
- `edc.iam.did.web.use.https=false` is set in the config files (EDC defaults to HTTPS for did:web)

### Connection refused

- Check the required ports are open in your cloud provider's NSG/firewall
- On the VM, check local firewall rules: `sudo iptables -L -n` or `sudo ufw status`
- Test basic connectivity from the remote machine: `nc -zv <host> 19194`

### Seed script fails

- Make sure all containers are healthy: `docker ps` (all should show `(healthy)`)
- Wait for IdentityHub to be ready: `curl http://localhost:7090/api/check/health`
- Check that `deployment/assets/issuer_private.pem` exists (run `./generate-keys.sh` from project root)
- Verify Python has the cryptography library: `python3 -c "from cryptography.hazmat.primitives import serialization"`
- Verify jq is installed: `jq --version`

### "MY_PUBLIC_HOST variable is not set" warning on docker compose down

This is harmless. Docker Compose reads `.env` on `down` to resolve variable references, but the values don't matter for stopping containers.

---

## Development Setup (Two Participants on One Machine)

For local development you can run two complete participant stacks on a single machine using the root `docker-compose.yml`. This simulates two independent organizations without needing separate hosts or cloud VMs.

### Architecture

```
Single dev machine
+-------------------------------------------------------------------------------+
| docker-compose.yml (project root)                                             |
|                                                                               |
| Participant 1                           Participant 2                         |
| ─────────────────────────               ─────────────────────────             |
| participant-1-identityhub  7090-96      participant-2-identityhub  7080-86    |
| participant-1-controlplane 18181        participant-2-controlplane 28181      |
|   mgmt:19193 DSP:19194                   mgmt:29193 DSP:29194                 |
| participant-1-dataplane    38181        participant-2-dataplane    48181      |
|   public:38185                            public:48185                        |
| participant-1-dashboard    3000         participant-2-dashboard    3001       |
| participant-1-vault        8200         participant-2-vault        8201       |
| participant-1-did-server   9876         participant-2-did-server   9877       |
|                                                                               |
| postgres  15432 (shared — separate databases per participant)                 |
+-------------------------------------------------------------------------------+
```

Each participant has its own Vault and DID server with independently generated issuer keys and VCs, matching the cloud deployment's multi-issuer trust model.

### Quick Start

From the **project root**:

```bash
# 1. Generate keys
./generate-keys.sh

# 2. Build all Docker images (controlplane, dataplane, identityhub, dashboard)
./gradlew dockerize

# 3. Start all services
docker compose up -d

# 4. Wait for all containers to be healthy
docker compose ps

# 5. Seed identity data for both participants
./deployment/seed.sh
```

### Dashboards

| Dashboard | URL | Participant |
|-----------|-----|-------------|
| Participant 1 | http://localhost:3000 | Controls participant-1's connector |
| Participant 2 | http://localhost:3001 | Controls participant-2's connector |

Both dashboards use the same Docker image. The root `docker-compose.yml` passes environment variables (`CP_HOST`, `CP_MGMT_PORT`, `DP_HOST`, etc.) to configure which connector each dashboard proxies to.

### Running the E2E test

```bash
./test-e2e.sh
```

This runs all 20 E2E steps with 23 assertions across both participants and exits with code 0 on success.
