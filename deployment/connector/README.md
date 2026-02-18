# Standalone Connector Deployment

Run a single self-contained EDC connector stack per machine. Each machine runs one Control Plane, one Data Plane, one Identity Hub, and one DID server. Connectors on different machines communicate over the network using DCP (Decentralized Claims Protocol) with did:web DIDs and Verifiable Credentials.

## Architecture

Each machine is fully independent — it generates its own keys, signs its own VCs, and serves its own issuer DID document. Trust between machines is established via DID resolution over the network: Machine B fetches Machine A's issuer DID document from `http://hostA:9876/.well-known/did.json` to get the public key for VC verification.

```
Machine A (192.168.1.50)              Machine B (192.168.1.51)
+-----------------------------+       +-----------------------------+
| docker-compose.yml          |       | docker-compose.yml          |
|                             |       |                             |
| identityhub        7090-96  |       | identityhub        7090-96  |
| controlplane       18181    |       | controlplane       18181    |
|   mgmt:19193 DSP:19194     | <---> |   mgmt:19193 DSP:19194     |
| dataplane          38181    |       | dataplane          38181    |
|   public:38185              |       |   public:38185              |
| dashboard          3000    |       | dashboard          3000    |
| http-receiver      4000    |       | http-receiver      4000    |
| did-server         9876    |       | did-server         9876    |
| vault              8200    |       | vault              8200    |
| postgres          15432    |       | postgres          15432    |
+-----------------------------+       +-----------------------------+
```

All machines use the same ports — no conflicts since they're on different hosts.

## Prerequisites

### Required on every machine

| Dependency | Version | What it's for | Install |
|-----------|---------|---------------|---------|
| **Docker** | 20.10+ | Runs all services as containers | [docs.docker.com/get-docker](https://docs.docker.com/get-docker/) |
| **Docker Compose** | v2+ (ships with Docker Desktop) | Orchestrates the 7-container stack | Included with Docker Desktop; Linux: `apt install docker-compose-plugin` |
| **Python 3** | 3.8+ | `seed.sh` uses it for VC signing and JSON processing | Most systems have it; otherwise `apt install python3` / `brew install python3` |
| **`cryptography` Python package** | any | EC key operations for VC JWT signing | `pip install cryptography` or `pip3 install cryptography` |
| **`jq`** | any | `seed.sh` parses JSON API responses | `apt install jq` / `brew install jq` |
| **`curl`** | any | `seed.sh` calls EDC management + IdentityHub APIs | Usually pre-installed; `apt install curl` |
| **`base64`** | any (coreutils) | `seed.sh` encodes DIDs for API paths | Pre-installed on Linux/macOS |
| **`openssl`** | 1.1+ | `generate-keys.sh` generates EC P-256 key pairs | Pre-installed on most systems; `apt install openssl` |

### Required only on the build machine

| Dependency | Version | What it's for | Install |
|-----------|---------|---------------|---------|
| **JDK** | 17+ | Compiles Java source and builds shadow JARs via Gradle | [adoptium.net](https://adoptium.net/) or `apt install openjdk-17-jdk` |

> The Gradle wrapper (`./gradlew`) is included in the repository — you do not need to install Gradle separately. The wrapper downloads the correct Gradle version automatically on first run.

> Machines that don't build from source can load pre-built Docker images instead (see [Distributing Docker Images](#distributing-docker-images)).

### Network requirements

All machines must be able to reach each other on the ports listed in [Ports That Must Be Reachable](#ports-that-must-be-reachable). If you're behind a firewall or NAT, use a VPN/mesh like [Tailscale](https://tailscale.com/) to make the machines directly routable.

## Key Concepts

### Independent Keys Per Machine

Each machine runs `generate-keys.sh` to create its own:
- **Issuer key pair** (`deployment/assets/issuer_private.pem`) — signs MembershipCredentials
- **Data plane token keys** (`config/certs/private-key.pem`, `public-key.pem`) — signs/verifies EDR tokens

Private keys never leave the machine. Public keys are shared via DID documents served over HTTP.

### Multiple Trusted Issuers

Since each machine is its own VC issuer, all machines must trust each other's issuer DIDs. The `TRUSTED_ISSUER_DIDS` environment variable is a comma-separated list of all issuer DIDs in the dataspace, passed to the Control Plane via `-Dedc.demo.dcp.trusted.issuer.dids`.

Each machine's issuer DID follows the pattern `did:web:<host>%3A9876`, where `<host>` is the machine's `MY_PUBLIC_HOST` value. For example, with two machines at `192.168.1.50` and `192.168.1.51`:

```
TRUSTED_ISSUER_DIDS=did:web:192.168.1.50%3A9876,did:web:192.168.1.51%3A9876
```

This value must be identical on all machines in the dataspace.

### `MY_PUBLIC_HOST`

The IP or hostname that **other machines** will use to reach **this machine**. It gets injected into:

- **DID identifiers**: `did:web:<MY_PUBLIC_HOST>%3A7093`
- **DSP callback URLs**: `http://<MY_PUBLIC_HOST>:19194/protocol`
- **Data plane public URL**: `http://<MY_PUBLIC_HOST>:38185/public`
- **IdentityHub hostname**: so DID documents resolve correctly
- **Issuer DID document**: `did:web:<MY_PUBLIC_HOST>%3A9876`

Must be routable from inside Docker containers on the remote machine — `localhost` will NOT work.

## Choosing `MY_PUBLIC_HOST`

### Same LAN

Use each machine's LAN IP:

```bash
# Linux
hostname -I | awk '{print $1}'

# macOS
ipconfig getifaddr en0
```

### Different networks (Tailscale)

[Tailscale](https://tailscale.com/) creates a private WireGuard mesh. Each machine gets a stable IP (e.g. `100.64.x.x`) that works across any network, with all ports automatically reachable.

```bash
# Install: https://tailscale.com/download
tailscale up
tailscale ip -4     # use this as MY_PUBLIC_HOST
```

### Single-machine testing

Use the Docker bridge gateway IP:

```bash
# Linux (usually 172.17.0.1)
ip addr show docker0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1

# macOS / Windows (Docker Desktop)
# Use: host.docker.internal
```

## Quick Start

All commands are run from the **project root** unless noted otherwise.

### 1. Generate keys (once per machine)

```bash
./generate-keys.sh
```

This creates:
- `config/certs/private-key.pem` and `public-key.pem` (data plane token keys)
- `deployment/assets/issuer_private.pem` and `issuer_public.pem` (VC issuer keys)

If the keys already exist, the script skips them. Delete them to regenerate.

### 2. Build Docker images (build machine only)

```bash
./gradlew dockerize
```

This produces three local Docker images: `controlplane:latest`, `dataplane:latest`, `identityhub:latest`.

If other machines won't build from source, export and copy the images (see [Distributing Docker Images](#distributing-docker-images)).

### 3. Configure environment

```bash
cd deployment/connector
cp .env.example .env
```

Edit `.env` with your values:

```bash
# This machine's routable IP or hostname
MY_PUBLIC_HOST=192.168.1.50

# Comma-separated list of ALL issuer DIDs in the dataspace (including this machine)
TRUSTED_ISSUER_DIDS=did:web:192.168.1.50%3A9876,did:web:192.168.1.51%3A9876
```

### 4. Start the stack

```bash
docker compose up -d
```

Wait for all containers to be healthy:

```bash
docker ps
```

All 7 containers should show `(healthy)`. This typically takes 30-60 seconds.

### 5. Seed identity data

```bash
MY_PUBLIC_HOST=192.168.1.50 ./seed.sh
```

The seed script:
1. Generates a MembershipCredential VC (signed with this machine's issuer key)
2. Creates a participant context in IdentityHub
3. Publishes the participant's DID document
4. Stores the STS client secret in the Control Plane's vault
5. Stores the MembershipCredential in IdentityHub
6. Updates the issuer DID document on the DID server (nginx)

### 6. Open the dashboard

The dashboard is available at **http://localhost:3000**. It shows health status for all three services (Control Plane, Data Plane, IdentityHub) and provides a UI for managing assets, policies, contracts, and transfers.

No extra configuration is needed — the dashboard image uses ENV defaults that match the standalone service names (`controlplane`, `dataplane`, `identityhub`) and ports.

### 7. Repeat on every other machine

Each machine generates its own keys, builds (or loads) images, starts its stack, and runs its own seed script. The only shared configuration is `TRUSTED_ISSUER_DIDS` — all machines must list the same set of issuer DIDs.

### 8. Verify cross-machine connectivity

From any machine, verify you can reach another machine's endpoints:

```bash
# Should return a DID document JSON
curl http://<OTHER_HOST>:9876/.well-known/did.json

# Should return a JSON error (not connection refused)
curl http://<OTHER_HOST>:19194/protocol
```

## End-to-End Example (Two Machines)

Machine A (`192.168.1.50`) is the **provider**, Machine B (`192.168.1.51`) is the **consumer**.

Replace `<HOST_A>` with Machine A's IP and `<DID_A>` with `did:web:192.168.1.50%3A7093`.

### On Machine A: Create Asset, Policy, and Contract (Steps 1-3)

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

#### 4. Request Catalog from Machine A

```bash
curl -X POST http://localhost:19193/management/v3/catalog/request \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@type": "CatalogRequest",
    "counterPartyAddress": "http://<HOST_A>:19194/protocol",
    "counterPartyId": "<DID_A>",
    "protocol": "dataspace-protocol-http"
  }'
```

Find `dcat:dataset` -> `odrl:hasPolicy` -> `@id` in the response. That's the **offer ID**.

#### 5. Negotiate a Contract

```bash
curl -X POST http://localhost:19193/management/v3/contractnegotiations \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/", "odrl": "http://www.w3.org/ns/odrl/2/" },
    "@type": "ContractRequest",
    "counterPartyAddress": "http://<HOST_A>:19194/protocol",
    "counterPartyId": "<DID_A>",
    "protocol": "dataspace-protocol-http",
    "policy": {
      "@type": "odrl:Offer",
      "@id": "<OFFER_ID>",
      "odrl:target": { "@id": "sample-asset-1" },
      "odrl:assigner": { "@id": "<DID_A>" },
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
    "counterPartyAddress": "http://<HOST_A>:19194/protocol",
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

Reuse the contract agreement from step 5. Replace `<HOST_B>` with Machine B's IP:

```bash
curl -X POST http://localhost:19193/management/v3/transferprocesses \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "http://<HOST_A>:19194/protocol",
    "counterPartyId": "<DID_A>",
    "protocol": "dataspace-protocol-http",
    "contractId": "<AGREEMENT_ID>",
    "assetId": "sample-asset-1",
    "transferType": "HttpData-PUSH",
    "dataDestination": {
      "type": "HttpData",
      "baseUrl": "http://<HOST_B>:4000/"
    }
  }'
```

Once the transfer reaches `COMPLETED`, verify the data arrived:

```bash
curl http://localhost:4000/
```

## Development Setup (Two Participants on One Machine)

For local development you can run two complete participant stacks on a single machine using the root `docker-compose.yml`. This simulates two independent organizations without needing separate hosts.

### Architecture

```
Single dev machine
+--------------------------------------------------------------------------+
| docker-compose.yml (project root)                                        |
|                                                                          |
| Participant 1                           Participant 2                    |
| ─────────────────────────               ─────────────────────────        |
| participant-1-identityhub  7090-96      participant-2-identityhub  7080-86  |
| participant-1-controlplane 18181        participant-2-controlplane 28181    |
|   mgmt:19193 DSP:19194                   mgmt:29193 DSP:29194              |
| participant-1-dataplane    38181        participant-2-dataplane    48181    |
|   public:38185                            public:48185                     |
| participant-1-dashboard    3000         participant-2-dashboard    3001     |
| participant-1-vault        8200         participant-2-vault        8201     |
| participant-1-did-server   9876         participant-2-did-server   9877     |
|                                                                          |
| postgres  15432 (shared — separate databases per participant)            |
+--------------------------------------------------------------------------+
```

Each participant has its own Vault and DID server with independently generated issuer keys and VCs, matching the standalone deployment's multi-issuer trust model.

Each participant gets its own dashboard instance, configured at runtime via environment variables to point at its respective connector services.

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

## Distributing Docker Images

If a machine doesn't have the source code or JDK to build images, transfer pre-built images:

```bash
# On the build machine
docker save controlplane:latest dataplane:latest identityhub:latest | gzip > edc-images.tar.gz

# Copy to the other machine
scp edc-images.tar.gz user@machine-b:~/

# On the other machine
docker load < edc-images.tar.gz
```

The tarball is typically ~300-400 MB. Machines that load images this way still need:
- The repository files (for config, `seed.sh`, `docker-compose.yml`, `generate-keys.sh`)
- Python 3 + `cryptography` + `jq` + `curl` (for `seed.sh`)
- OpenSSL (for `generate-keys.sh`)

The simplest approach is to clone the repository on every machine. Alternatively, copy just the required files:

```bash
# Minimal set of files needed on a non-build machine
deployment/connector/         # docker-compose.yml, seed.sh, .env.example
deployment/nginx.conf         # nginx config for DID server
deployment/http-receiver/     # push transfer test receiver
config/docker/*-connector.*   # runtime config files
config/certs/                 # generated after running generate-keys.sh
deployment/assets/            # generated after running generate-keys.sh
generate-keys.sh              # key generation script
```

## Ports That Must Be Reachable

Remote machines need to reach these ports on this machine:

| Port | Service | Why |
|------|---------|-----|
| 7091 | IdentityHub Credentials API | VP/VC presentation requests |
| 7093 | IdentityHub DID endpoint | Participant DID document resolution |
| 9876 | DID Server (nginx) | Issuer DID document resolution |
| 19194 | Control Plane DSP | Catalog requests, negotiation/transfer callbacks |
| 38185 | Data Plane public | Data fetch via EDR token (pull transfers) |
| 4000 | http-receiver | Push transfer destination (test only) |

Dashboard (3000) and management port (19193) only need to be reachable from your local terminal, not from remote machines.

### Verifying port connectivity

From the remote machine, test each critical port:

```bash
# Issuer DID resolution (should return JSON)
curl http://<HOST>:9876/.well-known/did.json

# DSP endpoint (should return a JSON error, not connection refused)
curl http://<HOST>:19194/protocol

# IdentityHub DID endpoint (should respond, even if 404)
curl http://<HOST>:7093/.well-known/did.json
```

## Adding a Third (or More) Machine

1. Generate keys on the new machine: `./generate-keys.sh`
2. Update `TRUSTED_ISSUER_DIDS` in `.env` on **all** machines to include the new machine's issuer DID (`did:web:<new-host>%3A9876`)
3. Restart the control planes on existing machines so they pick up the new trusted issuer:
   ```bash
   cd deployment/connector
   docker compose restart controlplane
   ```
4. Start the stack on the new machine and run `seed.sh`

## Resetting a Machine

To wipe all state and start fresh:

```bash
cd deployment/connector
docker compose down -v    # stops containers AND deletes volumes (DB data, DID docs)
```

Then re-run from step 4 of the [Quick Start](#4-start-the-stack). Keys don't need to be regenerated unless you want new ones.

## Troubleshooting

### 401 Unauthorized on catalog/negotiation

- Verify `TRUSTED_ISSUER_DIDS` includes **all** machines' issuer DIDs on **all** machines
- Verify the remote issuer DID document is accessible: `curl http://<remote-host>:9876/.well-known/did.json`
- Check that `MY_PUBLIC_HOST` is correct and reachable from the other machine's Docker containers
- After changing `TRUSTED_ISSUER_DIDS`, you must restart the control plane: `docker compose restart controlplane`

### DID resolution failures

- Verify the IdentityHub DID endpoint is accessible from the remote machine: `curl http://<host>:7093/.well-known/did.json`
- `edc.iam.did.web.use.https=false` is set in the config files (EDC defaults to HTTPS for did:web)

### Connection refused

- Check the required ports are open between machines (see ports table above)
- On Linux, check firewall rules: `sudo iptables -L -n` or `sudo ufw status`
- Test basic connectivity: `nc -zv <remote-host> 19194`

### Seed script fails

- Make sure all containers are healthy: `docker ps` (all should show `(healthy)`)
- Wait for IdentityHub to be ready: `curl http://localhost:7090/api/check/health`
- Check that `deployment/assets/issuer_private.pem` exists (run `./generate-keys.sh` from project root)
- Verify Python has the cryptography library: `python3 -c "from cryptography.hazmat.primitives import serialization"`
- Verify jq is installed: `jq --version`

### "MY_PUBLIC_HOST variable is not set" warning on docker compose down

This is harmless. Docker Compose reads the `.env` file on `down` to resolve variable references in the compose file, but the values don't matter for stopping containers. You can ignore this warning.
