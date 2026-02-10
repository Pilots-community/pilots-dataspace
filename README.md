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

This script runs all 10 E2E steps (pull + push transfers) with assertions and exits with code 0 on success. CI runs it automatically on every push and PR to `main`.

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
| Provider Control Plane | `config/controlplane.properties` | default: 18181, mgmt: 19193, DSP: 19194, control: 19192 |
| Consumer Control Plane | `config/controlplane-consumer.properties` | default: 28181, mgmt: 29193, DSP: 29194, control: 29192 |
| Provider Data Plane | `config/dataplane.properties` | default: 38181, control: 38182, public: 38185 |
| Consumer Data Plane | `config/dataplane-consumer.properties` | default: 48181, control: 48182, public: 48185 |
| Provider IdentityHub | `config/identityhub-provider.properties` | base: 7090, creds: 7091, identity: 7092, DID: 7093, version: 7095, STS: 7096 |
| Consumer IdentityHub | `config/identityhub-consumer.properties` | base: 7080, creds: 7081, identity: 7082, DID: 7083, version: 7085, STS: 7086 |
| DID Server (NGINX) | — | 9876 |

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
# Terminal 1: Provider Control Plane
java -Dedc.fs.config=config/controlplane.properties \
     -jar runtimes/controlplane/build/libs/controlplane.jar

# Terminal 2: Consumer Control Plane
java -Dedc.fs.config=config/controlplane-consumer.properties \
     -jar runtimes/controlplane/build/libs/controlplane.jar

# Terminal 3: Provider Data Plane
java -Dedc.fs.config=config/dataplane.properties \
     -jar runtimes/dataplane/build/libs/dataplane.jar

# Terminal 4: Consumer Data Plane
java -Dedc.fs.config=config/dataplane-consumer.properties \
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
CREATE DATABASE provider_controlplane OWNER edc;
CREATE DATABASE consumer_controlplane OWNER edc;
CREATE DATABASE provider_dataplane OWNER edc;
CREATE DATABASE consumer_dataplane OWNER edc;
SQL
```

The schema bootstrapper will create tables automatically when each runtime starts.

## Distributed Deployment (Multi-Machine)

To run connectors on separate machines communicating over a network tunnel, see [`deployment/distributed/README.md`](deployment/distributed/README.md).

## Verify Health

```bash
# Provider Control Plane
curl http://localhost:18181/api/check/health

# Consumer Control Plane
curl http://localhost:28181/api/check/health

# Data Plane
curl http://localhost:38181/api/check/health
```

## End-to-End Example: Catalog, Negotiate, Transfer

> **Provider** = the connector that owns the data (management API on port **19193**)
> **Consumer** = the connector requesting access (management API on port **29193**)

Steps 1-3 set up data on the provider. Steps 4-7 run a pull transfer (consumer fetches data via EDR). Steps 8-10 run a push transfer (provider pushes data to an HTTP endpoint).

### Environment Variables

Set these once before running the steps below. The values differ between native and Docker Compose because the `counterPartyAddress` uses Docker service names for container-to-container communication, and the `counterPartyId` / provider DID depends on the IdentityHub hostname.

**Native:**

```bash
PROVIDER_DSP="http://localhost:19194/protocol"
PROVIDER_DID="did:web:localhost%3A7093"
```

**Docker Compose:**

```bash
PROVIDER_DSP="http://provider-controlplane:19194/protocol"
PROVIDER_DID="did:web:provider-identityhub%3A7093"
```

### 1. Create an Asset on the Provider

Register a data source on the provider. This example exposes a public JSON API as an asset:

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

Create an open (permit-all) policy on the provider. In production you would add constraints here:

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

Link the asset to the policy on the provider. This makes the asset visible in the provider's catalog:

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

### 4. Request the Catalog (from Consumer)

Ask the consumer to fetch the provider's catalog. `counterPartyAddress` tells the consumer where to find the provider's DSP endpoint. `counterPartyId` must be the provider's DID — this is required for DCP authentication (the consumer uses it as the JWT audience when requesting an STS token).

```bash
curl -s -X POST http://localhost:29193/management/v3/catalog/request \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d "{
    \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
    \"counterPartyAddress\": \"${PROVIDER_DSP}\",
    \"counterPartyId\": \"${PROVIDER_DID}\",
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
    \"counterPartyAddress\": \"${PROVIDER_DSP}\",
    \"counterPartyId\": \"${PROVIDER_DID}\",
    \"protocol\": \"dataspace-protocol-http\"
  }" | jq -r '.["dcat:dataset"]["odrl:hasPolicy"]["@id"]')

echo "$OFFER_ID"
```

It looks like a Base64-encoded string, e.g. `c2FtcGxlLWNvbnRyYWN0LWRlZg==:c2FtcGxlLWFzc2V0LTE=:MjdlNDFh...`

### 5. Negotiate a Contract

Start a contract negotiation on the consumer side using the offer ID from step 4. The `assigner` must be the provider's DID.

```bash
NEGOTIATION_ID=$(curl -s -X POST http://localhost:29193/management/v3/contractnegotiations \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d "{
    \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
    \"counterPartyAddress\": \"${PROVIDER_DSP}\",
    \"counterPartyId\": \"${PROVIDER_DID}\",
    \"protocol\": \"dataspace-protocol-http\",
    \"policy\": {
      \"@context\": \"http://www.w3.org/ns/odrl.jsonld\",
      \"@id\": \"${OFFER_ID}\",
      \"@type\": \"Offer\",
      \"assigner\": \"${PROVIDER_DID}\",
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
    \"counterPartyAddress\": \"${PROVIDER_DSP}\",
    \"counterPartyId\": \"${PROVIDER_DID}\",
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

The response contains an `endpoint` URL and an `authorization` token. When running with Docker Compose, the `endpoint` shows the Docker service name (`http://provider-dataplane:38185/public`) — from your host terminal use `localhost` instead. Extract the token and fetch the actual data:

```bash
TOKEN=$(curl -s http://localhost:29193/management/v3/edrs/$TRANSFER_ID/dataaddress \
  -H "X-Api-Key: password" | jq -r '.authorization')

curl -s http://localhost:38185/public \
  -H "Authorization: Bearer $TOKEN" | jq .
```

A successful response returns the actual data from the asset's source URL (e.g., the JSON from `jsonplaceholder.typicode.com`). This confirms the full DCP-authenticated data transfer pipeline is working — token issuance, credential presentation, contract enforcement, EDR validation, and data proxying all passed.

### 8. Push Transfer (HttpData-PUSH)

Instead of the consumer pulling data via an EDR token, the provider data plane can **push** data directly to a consumer-specified HTTP endpoint. The `http-receiver` service in Docker Compose provides a simple endpoint for testing this.

Reuse the same contract agreement from step 5. Specify `HttpData-PUSH` as the transfer type and a `dataDestination` with the receiver URL:

```bash
PUSH_TRANSFER_ID=$(curl -s -X POST http://localhost:29193/management/v3/transferprocesses \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d "{
    \"@context\": { \"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\" },
    \"counterPartyAddress\": \"${PROVIDER_DSP}\",
    \"counterPartyId\": \"${PROVIDER_DID}\",
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
