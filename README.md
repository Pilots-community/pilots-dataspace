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

### 1. Create an Asset on the Provider

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

An open (permit-all) policy for the demo:

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

Links the asset to the policy, making it visible in the catalog:

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

```bash
curl -X POST http://localhost:29193/management/v3/catalog/request \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "http://localhost:19194/protocol",
    "protocol": "dataspace-protocol-http"
  }'
```

The response will contain a `dcat:dataset` with an `odrl:hasPolicy` field. Copy the `@id` of the policy (the offer ID) for the next step.

### 5. Negotiate a Contract

Replace `<OFFER_ID>` with the offer ID from the catalog response:

```bash
curl -X POST http://localhost:29193/management/v3/contractnegotiations \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "http://localhost:19194/protocol",
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

Check negotiation status (replace `<NEGOTIATION_ID>` with the returned `@id`):

```bash
curl http://localhost:29193/management/v3/contractnegotiations/<NEGOTIATION_ID> \
  -H "X-Api-Key: password"
```

Wait until `state` is `FINALIZED`, then note the `contractAgreementId`.

### 6. Initiate a Data Transfer

Replace `<AGREEMENT_ID>` with the contract agreement ID:

```bash
curl -X POST http://localhost:29193/management/v3/transferprocesses \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: password" \
  -d '{
    "@context": { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" },
    "counterPartyAddress": "http://localhost:19194/protocol",
    "protocol": "dataspace-protocol-http",
    "contractId": "<AGREEMENT_ID>",
    "assetId": "sample-asset-1",
    "transferType": "HttpData-PULL"
  }'
```

Check transfer status (replace `<TRANSFER_ID>`):

```bash
curl http://localhost:29193/management/v3/transferprocesses/<TRANSFER_ID> \
  -H "X-Api-Key: password"
```

Wait until `state` is `STARTED`.

### 7. Fetch Data via EDR

Get the Endpoint Data Reference (EDR) containing the access token:

```bash
curl http://localhost:29193/management/v3/edrs/<TRANSFER_ID>/dataaddress \
  -H "X-Api-Key: password"
```

The response contains `endpoint` and `authorization` fields. Use the token to fetch data through the data plane:

```bash
curl http://localhost:38185/public \
  -H "Authorization: Bearer <TOKEN>"
```

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
