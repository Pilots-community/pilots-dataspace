# Pilots Dataspace

A downstream project based on [Eclipse Dataspace Components (EDC)](https://github.com/eclipse-edc/Connector) that provides Control Plane, Data Plane, and IdentityHub runtimes for building custom dataspace solutions with DCP-based identity.

## Prerequisites

- Java 17+
- Gradle (wrapper included)
- Docker and Docker Compose (for containerized deployment)
- `jq` and `curl` (for running the seed script)
- Python 3 with the `cryptography` library (`pip install cryptography`)

> **Windows users:** The setup scripts and tooling require a bash shell. Use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) (recommended) or Git Bash.

## Quick Start

Run a single command to generate keys, build images, start all services, and seed identity data:

```bash
./setup.sh
```

To restart services without rebuilding (e.g. after a reboot or `docker compose down`):

```bash
./start.sh
```

Both scripts support `--clean` to wipe volumes (database, vault) and start fresh.

Once the script completes, follow the [End-to-End Example](#end-to-end-example-catalog-negotiate-transfer) to create an asset, negotiate a contract, and transfer data. Or run the automated E2E test:

```bash
./test-e2e.sh
```

This script runs all 20 E2E steps with 23 assertions — forward direction (participant-1-to-participant-2 pull + push transfers) and reverse direction (participant-2-to-participant-1 pull + push transfers) — and exits with code 0 on success. CI runs it automatically on every push and PR to `main`.

## Build

```bash
./gradlew build
```

This produces:
- `runtimes/controlplane/build/libs/controlplane.jar` (shadow JAR)
- `runtimes/dataplane/build/libs/dataplane.jar` (shadow JAR)
- `runtimes/identityhub/build/libs/identityhub.jar` (shadow JAR)

## Architecture

### Identity

This project uses the **Decentralized Claims Protocol (DCP)** for identity, replacing the `iam-mock` module. Each participant has:
- An **IdentityHub** instance with an embedded STS (Secure Token Service) that publishes a `did:web` DID document and handles credential presentation
- A **Control Plane** configured to authenticate via the STS and resolve DIDs over HTTP
- A **dataspace issuer** DID hosted as a static file via NGINX, used to sign MembershipCredentials

### Port Allocation

| Component | Config File | Ports |
|-----------|------------|-------|
| Participant-1 Control Plane | `config/controlplane-participant-1.properties` | default: 18181, mgmt: 19193, DSP: 19194, control: 19192 |
| Participant-2 Control Plane | `config/controlplane-participant-2.properties` | default: 28181, mgmt: 29193, DSP: 29194, control: 29192 |
| Participant-1 Data Plane | `config/dataplane-participant-1.properties` | default: 38181, control: 38182, public: 38185 |
| Participant-2 Data Plane | `config/dataplane-participant-2.properties` | default: 48181, control: 48182, public: 48185 |
| Participant-1 IdentityHub | `config/identityhub-participant-1.properties` | base: 7090, creds: 7091, identity: 7092, DID: 7093, version: 7095, STS: 7096 |
| Participant-2 IdentityHub | `config/identityhub-participant-2.properties` | base: 7080, creds: 7081, identity: 7082, DID: 7083, version: 7085, STS: 7086 |
| DID Server (NGINX) | — | 9876 |

## Deployment Options

This project supports three deployment modes. The dev setup (documented below) runs everything on a single machine for local development. The other two are for multi-machine scenarios where connectors on separate networks need to communicate.

| Mode | Location | Use case |
|------|----------|----------|
| **Dev (single machine)** | `docker-compose.yml` (root) | Local development — 2 participants on one machine, Docker-internal networking. Documented in this README. |
| **Standalone connector (1 per machine)** | [`deployment/connector/`](deployment/connector/README.md) | Production-like — one self-contained connector stack per machine, each with independent keys and its own VC issuer. |

The **standalone connector** deployment is the target for real-world use: each organization runs one connector on their own infrastructure. See its [README](deployment/connector/README.md) for full setup instructions, prerequisites, and an end-to-end walkthrough.

## Generate Keys and Credentials

Run this once before building or starting services. It generates all private keys, the issuer DID document, and pre-signed Verifiable Credentials:

```bash
./generate-keys.sh
```

Requires Python 3 with the `cryptography` library (`pip install cryptography`).

Private keys are gitignored and never committed to the repository. Each developer/machine generates its own keys.

## Run Locally

Start all three runtimes in separate terminals:

```bash
# Terminal 1: Participant-1 Control Plane
java -Dedc.fs.config=config/controlplane-participant-1.properties \
     -jar runtimes/controlplane/build/libs/controlplane.jar

# Terminal 2: Participant-2 Control Plane
java -Dedc.fs.config=config/controlplane-participant-2.properties \
     -jar runtimes/controlplane/build/libs/controlplane.jar

# Terminal 3: Participant-1 Data Plane
java -Dedc.fs.config=config/dataplane-participant-1.properties \
     -jar runtimes/dataplane/build/libs/dataplane.jar

# Terminal 4: Participant-2 Data Plane
java -Dedc.fs.config=config/dataplane-participant-2.properties \
     -jar runtimes/dataplane/build/libs/dataplane.jar
```

## Run with Docker Compose

Prerequisites:
- Docker and Docker Compose
- Token signing keys generated (see [Generate Token Signing Keys](#generate-token-signing-keys))

Build the Docker images and start all services:

```bash
./gradlew dockerize
docker compose up -d
```

Wait for all services to become healthy, then seed the identity data:

```bash
# Wait for health checks to pass
docker compose ps  # all services should show "healthy"

# Seed participant contexts and credentials into IdentityHubs,
# and store STS client secrets in connector vaults
./deployment/seed.sh
```

All runtimes will start and register as healthy. Ports are mapped 1:1 to the host, so health checks and management API calls use the same `localhost` URLs as native mode.

To stop the services:

```bash
docker compose down
```


## HashiCorp Vault

All runtimes use [HashiCorp Vault](https://www.vaultproject.io/) for secret management, replacing EDC's default in-memory vault.

### Docker Compose

Vault runs in dev mode and starts automatically alongside the other services. The dev root token is `root-token` and the UI is accessible at `http://localhost:8200`.

### Local / Native Runs

When running runtimes directly with `java -jar`, you need a local Vault instance:

```bash
# Install Vault (if not already installed)
# Ubuntu/Debian: sudo apt install vault
# macOS: brew install vault

# Start Vault in dev mode
vault server -dev -dev-root-token-id=root-token
```

Vault must be running before starting the EDC runtimes. The config files point to `http://localhost:8200` with token `root-token`.

## PostgreSQL Persistence

All runtimes use PostgreSQL for persistent storage. With `edc.sql.schema.autocreate=true`, EDC's built-in `SqlSchemaBootstrapper` automatically creates all required tables on startup.

### Docker Compose

PostgreSQL is included in the Docker Compose setup and starts automatically. No manual database setup is needed.

```bash
docker compose up       # starts Vault, PostgreSQL + all EDC runtimes
docker compose down     # stops services, data is preserved in the postgres-data volume
docker compose down -v  # stops services and deletes the database volume (clean reset)
```

### Local / Native Runs

When running runtimes directly with `java -jar`, you need a local PostgreSQL instance:

```bash
# Install PostgreSQL (if not already installed)
# Ubuntu/Debian: sudo apt install postgresql
# macOS: brew install postgresql

# Create the user and databases
sudo -u postgres psql <<'SQL'
CREATE USER edc WITH PASSWORD 'edc';
CREATE DATABASE participant_1_controlplane OWNER edc;
CREATE DATABASE participant_2_controlplane OWNER edc;
CREATE DATABASE participant_1_dataplane OWNER edc;
CREATE DATABASE participant_2_dataplane OWNER edc;
SQL
```

The schema bootstrapper will create tables automatically when each runtime starts.

## Verify Health

```bash
# Participant-1 Control Plane
curl http://localhost:18181/api/check/health

# Participant-2 Control Plane
curl http://localhost:28181/api/check/health

# Participant-1 Data Plane
curl http://localhost:38181/api/check/health
```

## End-to-End Example: Catalog, Negotiate, Transfer

> **Participant-1** = the connector that owns the data in the forward direction (management API on port **19193**)
> **Participant-2** = the connector requesting access in the forward direction (management API on port **29193**)

Steps 1-3 set up data on participant-1. Steps 4-7 run a pull transfer (participant-2 fetches data via EDR). Steps 8-10 run a push transfer (participant-1 pushes data to an HTTP endpoint). Steps 11-14 test the **reverse direction** — participant-2 owns data and participant-1 requests it — proving bidirectional data sharing works.

### Environment Variables

Set these once before running the steps below. The values differ between native and Docker Compose because the `counterPartyAddress` uses Docker service names for container-to-container communication, and the `counterPartyId` / participant DID depends on the IdentityHub hostname.

**Native:**

```bash
P1_DSP="http://localhost:19194/protocol"
P1_DID="did:web:localhost%3A7093"
P2_DSP="http://localhost:29194/protocol"
P2_DID="did:web:localhost%3A7083"
```

**Docker Compose:**

```bash
P1_DSP="http://participant-1-controlplane:19194/protocol"
P1_DID="did:web:participant-1-identityhub%3A7093"
P2_DSP="http://participant-2-controlplane:29194/protocol"
P2_DID="did:web:participant-2-identityhub%3A7083"
```

### 1. Create an Asset on Participant-1

Register a data source on participant-1. This example exposes a public JSON API as an asset:

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

### 2. Create a Policy Definition

Create an open (permit-all) policy on participant-1. In production you would add constraints here:

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

### 3. Create a Contract Definition

Link the asset to the policy on participant-1. This makes the asset visible in participant-1's catalog:

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

### 4. Request the Catalog (from Participant-2)

Ask the consumer to fetch participant-1's catalog. `counterPartyAddress` tells the consumer where to find participant-1's DSP endpoint. `counterPartyId` must be participant-1's DID — this is required for DCP authentication (the consumer uses it as the JWT audience when requesting an STS token).

```bash
curl -s -X POST http://localhost:29193/management/v3/catalog/request \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d "{
    \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
    \"counterPartyAddress\": \"${P1_DSP}\",
    \"counterPartyId\": \"${P1_DID}\",
    \"protocol\": \"dataspace-protocol-http\"
  }" | jq .
```

In the response, find the `dcat:dataset` entry for `sample-asset-1`. Inside it, `odrl:hasPolicy` contains the offer. Extract the **offer ID** (the `@id` of that policy) — you need it for the next step:

```bash
OFFER_ID=$(curl -s -X POST http://localhost:29193/management/v3/catalog/request \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d "{
    \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
    \"counterPartyAddress\": \"${P1_DSP}\",
    \"counterPartyId\": \"${P1_DID}\",
    \"protocol\": \"dataspace-protocol-http\"
  }" | jq -r '.["dcat:dataset"]["odrl:hasPolicy"]["@id"]')

echo "$OFFER_ID"
```

It looks like a Base64-encoded string, e.g. `c2FtcGxlLWNvbnRyYWN0LWRlZg==:c2FtcGxlLWFzc2V0LTE=:MjdlNDFh...`

### 5. Negotiate a Contract

Start a contract negotiation on the consumer side using the offer ID from step 4. The `assigner` must be participant-1's DID.

```bash
NEGOTIATION_ID=$(curl -s -X POST http://localhost:29193/management/v3/contractnegotiations \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d "{
    \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
    \"counterPartyAddress\": \"${P1_DSP}\",
    \"counterPartyId\": \"${P1_DID}\",
    \"protocol\": \"dataspace-protocol-http\",
    \"policy\": {
      \"@context\": \"http://www.w3.org/ns/odrl.jsonld\",
      \"@id\": \"${OFFER_ID}\",
      \"@type\": \"Offer\",
      \"assigner\": \"${P1_DID}\",
      \"target\": \"sample-asset-1\",
      \"permission\": [],
      \"prohibition\": [],
      \"obligation\": []
    }
  }" | jq -r '.["@id"]')

echo "$NEGOTIATION_ID"
```

Poll the negotiation status until `state` becomes `FINALIZED`:

```bash
curl -s http://localhost:29193/management/v3/contractnegotiations/$NEGOTIATION_ID \
  -H "X-Api-Key: password" | jq '{state, contractAgreementId}'
```

Once finalized, capture the `contractAgreementId`:

```bash
AGREEMENT_ID=$(curl -s http://localhost:29193/management/v3/contractnegotiations/$NEGOTIATION_ID \
  -H "X-Api-Key: password" | jq -r '.contractAgreementId')

echo "$AGREEMENT_ID"
```

### 6. Initiate a Data Transfer

Request a data transfer on the consumer side using the contract agreement ID from step 5:

```bash
TRANSFER_ID=$(curl -s -X POST http://localhost:29193/management/v3/transferprocesses \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d "{
    \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
    \"counterPartyAddress\": \"${P1_DSP}\",
    \"counterPartyId\": \"${P1_DID}\",
    \"protocol\": \"dataspace-protocol-http\",
    \"contractId\": \"${AGREEMENT_ID}\",
    \"assetId\": \"sample-asset-1\",
    \"transferType\": \"HttpData-PULL\"
  }" | jq -r '.["@id"]')

echo "$TRANSFER_ID"
```

Poll the transfer status until `state` becomes `STARTED`:

```bash
curl -s http://localhost:29193/management/v3/transferprocesses/$TRANSFER_ID \
  -H "X-Api-Key: password" | jq '{state, type}'
```

### 7. Fetch Data via EDR

Once the transfer is `STARTED`, retrieve the Endpoint Data Reference (EDR). This contains a short-lived access token for the data plane:

```bash
curl -s http://localhost:29193/management/v3/edrs/$TRANSFER_ID/dataaddress \
  -H "X-Api-Key: password" | jq .
```

The response contains an `endpoint` URL and an `authorization` token. When running with Docker Compose, the `endpoint` shows the Docker service name (`http://participant-1-dataplane:38185/public`) — from your host terminal use `localhost` instead. Extract the token and fetch the actual data:

```bash
TOKEN=$(curl -s http://localhost:29193/management/v3/edrs/$TRANSFER_ID/dataaddress \
  -H "X-Api-Key: password" | jq -r '.authorization')

curl -s http://localhost:38185/public \
  -H "Authorization: Bearer $TOKEN" | jq .
```

A successful response returns the actual data from the asset's source URL (e.g., the JSON from `jsonplaceholder.typicode.com`). This confirms the full DCP-authenticated data transfer pipeline is working — token issuance, credential presentation, contract enforcement, EDR validation, and data proxying all passed.

### 8. Push Transfer (HttpData-PUSH)

Instead of the consumer pulling data via an EDR token, the participant-1 data plane can **push** data directly to a consumer-specified HTTP endpoint. The `http-receiver` service in Docker Compose provides a simple endpoint for testing this.

Reuse the same contract agreement from step 5. Specify `HttpData-PUSH` as the transfer type and a `dataDestination` with the receiver URL:

```bash
PUSH_TRANSFER_ID=$(curl -s -X POST http://localhost:29193/management/v3/transferprocesses \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d "{
    \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
    \"counterPartyAddress\": \"${P1_DSP}\",
    \"counterPartyId\": \"${P1_DID}\",
    \"protocol\": \"dataspace-protocol-http\",
    \"contractId\": \"${AGREEMENT_ID}\",
    \"assetId\": \"sample-asset-1\",
    \"transferType\": \"HttpData-PUSH\",
    \"dataDestination\": {
      \"type\": \"HttpData\",
      \"baseUrl\": \"http://http-receiver:4000/\"
    }
  }" | jq -r '.["@id"]')

echo "$PUSH_TRANSFER_ID"
```

Unlike pull transfers which stay in `STARTED`, push transfers reach `COMPLETED` once the data has been delivered:

```bash
curl -s http://localhost:29193/management/v3/transferprocesses/$PUSH_TRANSFER_ID \
  -H "X-Api-Key: password" | jq '{state, type}'
```

Once completed, verify the data arrived at the receiver:

```bash
curl -s http://localhost:4000/ | jq .
```

### 9. Reverse Direction: Create Asset, Policy, and Contract on Participant-2

The previous steps tested the forward direction (participant-1 owns data, participant-2 requests it). To test the reverse — participant-2 owns data, participant-1 requests it — create an asset, policy, and contract definition on **participant-2's** management API (port 29193):

```bash
curl -X POST http://localhost:29193/management/v3/assets \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@id": "reverse-asset-1",
    "properties": {
      "name": "Participant-2 Data Asset",
      "description": "A dataset owned by participant-2",
      "contenttype": "application/json"
    },
    "dataAddress": {
      "type": "HttpData",
      "baseUrl": "https://jsonplaceholder.typicode.com/todos/2"
    }
  }'

curl -X POST http://localhost:29193/management/v3/policydefinitions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": {
      "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
      "odrl": "http://www.w3.org/ns/odrl/2/"
    },
    "@id": "reverse-open-policy",
    "policy": {
      "@context": "http://www.w3.org/ns/odrl.jsonld",
      "@type": "Set",
      "permission": [],
      "prohibition": [],
      "obligation": []
    }
  }'

curl -X POST http://localhost:29193/management/v3/contractdefinitions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "@id": "reverse-contract-def",
    "accessPolicyId": "reverse-open-policy",
    "contractPolicyId": "reverse-open-policy",
    "assetsSelector": []
  }'
```

### 10. Reverse: Participant-1 Requests Participant-2's Catalog and Negotiates

Now **participant-1** fetches participant-2's catalog and negotiates a contract. Note the roles are swapped — `counterPartyAddress` points to participant-2's DSP endpoint and `counterPartyId` is participant-2's DID:

```bash
REVERSE_OFFER_ID=$(curl -s -X POST http://localhost:19193/management/v3/catalog/request \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d "{
    \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
    \"counterPartyAddress\": \"${P2_DSP}\",
    \"counterPartyId\": \"${P2_DID}\",
    \"protocol\": \"dataspace-protocol-http\"
  }" | jq -r '.["dcat:dataset"] | if type == "array" then .[] else . end | select(.["@id"] == "reverse-asset-1") | .["odrl:hasPolicy"]["@id"]')

echo "$REVERSE_OFFER_ID"
```

Negotiate using participant-1's management API. The `assigner` is participant-2's DID:

```bash
REVERSE_NEGOTIATION_ID=$(curl -s -X POST http://localhost:19193/management/v3/contractnegotiations \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d "{
    \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
    \"counterPartyAddress\": \"${P2_DSP}\",
    \"counterPartyId\": \"${P2_DID}\",
    \"protocol\": \"dataspace-protocol-http\",
    \"policy\": {
      \"@context\": \"http://www.w3.org/ns/odrl.jsonld\",
      \"@id\": \"${REVERSE_OFFER_ID}\",
      \"@type\": \"Offer\",
      \"assigner\": \"${P2_DID}\",
      \"target\": \"reverse-asset-1\",
      \"permission\": [],
      \"prohibition\": [],
      \"obligation\": []
    }
  }" | jq -r '.["@id"]')

echo "$REVERSE_NEGOTIATION_ID"
```

Poll until `FINALIZED` and capture the agreement ID:

```bash
curl -s http://localhost:19193/management/v3/contractnegotiations/$REVERSE_NEGOTIATION_ID \
  -H "X-Api-Key: password" | jq '{state, contractAgreementId}'

REVERSE_AGREEMENT_ID=$(curl -s http://localhost:19193/management/v3/contractnegotiations/$REVERSE_NEGOTIATION_ID \
  -H "X-Api-Key: password" | jq -r '.contractAgreementId')
```

### 11. Reverse: Participant-1 Pulls Data and Fetches via EDR

Initiate a pull transfer from participant-1's side:

```bash
REVERSE_TRANSFER_ID=$(curl -s -X POST http://localhost:19193/management/v3/transferprocesses \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d "{
    \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
    \"counterPartyAddress\": \"${P2_DSP}\",
    \"counterPartyId\": \"${P2_DID}\",
    \"protocol\": \"dataspace-protocol-http\",
    \"contractId\": \"${REVERSE_AGREEMENT_ID}\",
    \"assetId\": \"reverse-asset-1\",
    \"transferType\": \"HttpData-PULL\"
  }" | jq -r '.["@id"]')

echo "$REVERSE_TRANSFER_ID"
```

Poll until `STARTED`, then retrieve the EDR and fetch data from the **participant-2 data plane** (port 48185):

```bash
REVERSE_TOKEN=$(curl -s http://localhost:19193/management/v3/edrs/$REVERSE_TRANSFER_ID/dataaddress \
  -H "X-Api-Key: password" | jq -r '.authorization')

curl -s http://localhost:48185/public \
  -H "Authorization: Bearer $REVERSE_TOKEN" | jq .
```

A successful response returns the JSON from `jsonplaceholder.typicode.com/todos/2`, confirming that bidirectional data sharing works — the participant-2 data plane can serve data just like the participant-1 data plane.

## Custom Extensions

### `extensions/example-extension`

Template extension demonstrating the EDC `ServiceExtension` interface.

### `extensions/dataplane-public-endpoint`

Provides three capabilities missing from the base `dataplane-base-bom`:

1. **Public endpoint generator** - Registers an `HttpData` endpoint generator function so the data plane can issue EDR tokens with a valid public endpoint URL
2. **Public API proxy** - Registers a JAX-RS controller on the `public` web context (port 38185) that authorizes EDR tokens and proxies requests to the actual data source URL
3. **Key loading** - Loads PEM signing keys from files into the vault at startup

### `extensions/superuser-seed`

Seeds a "super-user" admin participant context into IdentityHub at startup. This bootstraps participant management via the Identity API.

### `extensions/did-example-resolver`

Seeds a hardcoded EC key pair into the in-memory vault so DCP modules can sign/verify tokens. Development/demo convenience only.

### `extensions/dcp-patch`

Registers DCP infrastructure for the control plane: JWS 2020 signature suite, trusted dataspace issuer, default scope mapping (MembershipCredential), and JSON-LD transformers.

## Adding a New Extension

1. Create a directory under `extensions/`
2. Add a `build.gradle.kts` with `java-library` plugin and EDC SPI dependencies
3. Implement `ServiceExtension` with `@Extension` annotation
4. Register via SPI: `src/main/resources/META-INF/services/org.eclipse.edc.spi.system.ServiceExtension`
5. Add as dependency in the target runtime's `build.gradle.kts`
6. Include in `settings.gradle.kts`

## Docker

```bash
./gradlew dockerize                              # Build Docker images
./gradlew dockerize -Dplatform="linux/amd64"     # Specific platform
```
