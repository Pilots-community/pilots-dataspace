# Pilots Dataspace

A downstream project based on [Eclipse Dataspace Components (EDC)](https://github.com/eclipse-edc/Connector) that provides two runtimes (Control Plane and Data Plane) for building custom dataspace solutions.

## Prerequisites

- Java 17+
- Gradle (wrapper included)

## Build

```bash
./gradlew build
```

This produces:
- `runtimes/controlplane/build/libs/controlplane.jar` (shadow JAR)
- `runtimes/dataplane/build/libs/dataplane.jar` (shadow JAR)

## Architecture

| Component | Config File | Ports |
|-----------|------------|-------|
| Provider Control Plane | `config/controlplane.properties` | default: 18181, mgmt: 19193, DSP: 19194, control: 19192 |
| Consumer Control Plane | `config/controlplane-consumer.properties` | default: 28181, mgmt: 29193, DSP: 29194, control: 29192 |
| Provider Data Plane | `config/dataplane.properties` | default: 38181, control: 38182, public: 38185 |

## Generate Token Signing Keys

The data plane requires EC keys for signing EDR access tokens:

```bash
mkdir -p config/certs

# Generate EC private key
openssl ecparam -name prime256v1 -genkey -noout | \
  openssl pkcs8 -topk8 -nocrypt -out config/certs/private-key.pem

# Extract public key
openssl ec -in config/certs/private-key.pem -pubout -out config/certs/public-key.pem
```

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
```

## Run with Docker Compose

Prerequisites:
- Docker and Docker Compose
- Token signing keys generated (see [Generate Token Signing Keys](#generate-token-signing-keys))

Build the Docker images and start all services:

```bash
./gradlew dockerize
docker compose up
```

All three runtimes will start and register as healthy. Ports are mapped 1:1 to the host, so health checks and management API calls use the same `localhost` URLs as native mode.

To stop the services:

```bash
docker compose down
```

### Docker vs Native: `counterPartyAddress`

When running with Docker Compose, the containers communicate over a Docker network using service names. The `counterPartyAddress` field in API request bodies (catalog requests, negotiations, transfers) must use Docker service names instead of `localhost`:

| Native | Docker Compose |
|--------|---------------|
| `http://localhost:19194/protocol` | `http://provider-controlplane:19194/protocol` |

The management API URLs you `curl` from your terminal remain `localhost` in both modes. Only the `counterPartyAddress` (which tells one EDC runtime how to reach another) changes.

Similarly, the EDR `endpoint` returned by the consumer will contain the Docker service name (`http://provider-dataplane:38185/public`). When fetching data from the host, use `http://localhost:38185/public` instead.

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

This walkthrough assumes you are running with **Docker Compose** (`docker compose up`). All `curl` commands are run from your host terminal. If you are running natively instead, replace the `counterPartyAddress` service names with `localhost` (see [Docker vs Native: counterPartyAddress](#docker-vs-native-counterpartyaddress)).

> **Provider** = the connector that owns the data (management API on port **19193**)
> **Consumer** = the connector requesting access (management API on port **29193**)

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

Ask the consumer to fetch the provider's catalog. The `counterPartyAddress` tells the consumer runtime where to find the provider's DSP protocol endpoint — this uses the Docker service name because the containers communicate over the Docker network:

```bash
curl -X POST http://localhost:29193/management/v3/catalog/request \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "http://provider-controlplane:19194/protocol",
    "protocol": "dataspace-protocol-http"
  }'
```

In the response, find the `dcat:dataset` entry for `sample-asset-1`. Inside it, `odrl:hasPolicy` contains the offer. Copy the `@id` of that policy — this is the **offer ID** you need for the next step. It looks like a Base64-encoded string, e.g.:

```
c2FtcGxlLWNvbnRyYWN0LWRlZg==:c2FtcGxlLWFzc2V0LTE=:MjdlNDFh...
```

### 5. Negotiate a Contract

Start a contract negotiation on the consumer side. Replace `<OFFER_ID>` with the offer ID from step 4:

```bash
curl -X POST http://localhost:29193/management/v3/contractnegotiations \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "http://provider-controlplane:19194/protocol",
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

The response returns a negotiation `@id`. Poll the negotiation status until `state` becomes `FINALIZED` (replace `<NEGOTIATION_ID>` with the returned `@id`):

```bash
curl http://localhost:29193/management/v3/contractnegotiations/<NEGOTIATION_ID> \
  -H "X-Api-Key: password"
```

Once finalized, copy the `contractAgreementId` from the response — you need it for the transfer.

### 6. Initiate a Data Transfer

Request a data transfer on the consumer side. Replace `<AGREEMENT_ID>` with the contract agreement ID from step 5:

```bash
curl -X POST http://localhost:29193/management/v3/transferprocesses \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "http://provider-controlplane:19194/protocol",
    "protocol": "dataspace-protocol-http",
    "contractId": "<AGREEMENT_ID>",
    "assetId": "sample-asset-1",
    "transferType": "HttpData-PULL"
  }'
```

Poll the transfer status until `state` becomes `STARTED` (replace `<TRANSFER_ID>` with the returned `@id`):

```bash
curl http://localhost:29193/management/v3/transferprocesses/<TRANSFER_ID> \
  -H "X-Api-Key: password"
```

### 7. Fetch Data via EDR

Once the transfer is `STARTED`, retrieve the Endpoint Data Reference (EDR). This contains a short-lived access token for the data plane:

```bash
curl http://localhost:29193/management/v3/edrs/<TRANSFER_ID>/dataaddress \
  -H "X-Api-Key: password"
```

The response contains an `endpoint` URL and an `authorization` token. The `endpoint` will show the Docker service name (`http://provider-dataplane:38185/public`), but from your host terminal use `localhost` instead:

```bash
curl http://localhost:38185/public \
  -H "Authorization: Bearer <TOKEN>"
```

This returns the data from the asset's backing data source (in this example, the JSON from `jsonplaceholder.typicode.com/todos/1`).

## Custom Extensions

### `extensions/example-extension`

Template extension demonstrating the EDC `ServiceExtension` interface.

### `extensions/dataplane-public-endpoint`

Provides three capabilities missing from the base `dataplane-base-bom`:

1. **Public endpoint generator** - Registers an `HttpData` endpoint generator function so the data plane can issue EDR tokens with a valid public endpoint URL
2. **Public API servlet** - Registers a JAX-RS controller on the `public` web context (port 38185) to serve data transfer requests
3. **Key loading** - Loads PEM signing keys from files into the in-memory vault at startup

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
