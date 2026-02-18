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
| http-receiver      4000    |       | http-receiver      4000    |
| did-server         9876    |       | did-server         9876    |
| vault              8200    |       | vault              8200    |
| postgres          15432    |       | postgres          15432    |
+-----------------------------+       +-----------------------------+
```

All machines use the same ports — no conflicts since they're on different hosts.

## Key Concepts

### Independent Keys Per Machine

Each machine runs `generate-keys.sh` to create its own:
- **Issuer key pair** (`deployment/assets/issuer_private.pem`) — signs MembershipCredentials
- **Data plane token keys** (`config/certs/`) — signs/verifies EDR tokens

Private keys never leave the machine. Public keys are shared via DID documents served over HTTP.

### Multiple Trusted Issuers

Since each machine is its own issuer, all machines must trust each other's issuer DIDs. The `TRUSTED_ISSUER_DIDS` environment variable is a comma-separated list of all issuer DIDs in the dataspace, passed to the Control Plane via `-Dedc.demo.dcp.trusted.issuer.dids`.

### `MY_PUBLIC_HOST`

The IP or hostname that **other machines** will use to reach **this machine**. Injected into DID identifiers, DSP callback URLs, data plane public URLs, and the issuer DID document. Must be routable from inside Docker containers — `localhost` will NOT work.

## Prerequisites

- Docker and Docker Compose
- Docker images built (`./gradlew dockerize` from project root)
- Python 3 with the `cryptography` library (for VC generation in seed.sh)
- Keys generated (`./generate-keys.sh` from project root)
- All machines must be able to reach each other on the required ports

## Quick Start

### 1. Generate keys (once per machine)

```bash
./generate-keys.sh
```

### 2. Build Docker images

```bash
./gradlew dockerize
```

### 3. Configure and start

```bash
cd deployment/connector
cp .env.example .env
```

Edit `.env`:
```bash
MY_PUBLIC_HOST=192.168.1.50
TRUSTED_ISSUER_DIDS=did:web:192.168.1.50%3A9876,did:web:192.168.1.51%3A9876
```

Start the stack:
```bash
docker compose up -d
```

### 4. Seed identity data

```bash
MY_PUBLIC_HOST=192.168.1.50 ./seed.sh
```

### 5. Repeat on every other machine

Each machine generates its own keys, starts its own stack, and runs its own seed script. The only shared configuration is `TRUSTED_ISSUER_DIDS` — all machines must list the same set of issuer DIDs.

## End-to-End Example (Two Machines)

Machine A (`192.168.1.50`) is the **provider**, Machine B (`192.168.1.51`) is the **consumer**.

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

Replace `<HOST_A>` with `192.168.1.50` and `<DID_A>` with `did:web:192.168.1.50%3A7093`.

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

## Distributing Docker Images

If a machine doesn't have the source code to build images:

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
| 7091 | IdentityHub Credentials API | VP/VC presentation requests |
| 7093 | IdentityHub DID endpoint | DID document resolution |
| 9876 | DID Server (nginx) | Issuer DID document resolution |
| 19194 | Control Plane DSP | Catalog requests, negotiation callbacks |
| 38185 | Data Plane public | Data fetch via EDR token |
| 4000 | http-receiver | Push transfer destination |

Management port (19193) only needs to be reachable from your local terminal, not from remote machines.

## Adding a Third (or More) Machine

1. Generate keys on the new machine: `./generate-keys.sh`
2. Update `TRUSTED_ISSUER_DIDS` on **all** machines to include the new machine's issuer DID
3. Restart the control planes on existing machines so they pick up the new trusted issuer:
   ```bash
   docker compose restart controlplane
   ```
4. Start the stack on the new machine and run `seed.sh`

## Troubleshooting

### 401 Unauthorized on catalog/negotiation

- Verify `TRUSTED_ISSUER_DIDS` includes **both** machines' issuer DIDs on **both** machines
- Verify the issuer DID document is accessible: `curl http://<remote-host>:9876/.well-known/did.json`
- Check that `MY_PUBLIC_HOST` is correct and reachable from the other machine's Docker containers

### DID resolution failures

- Verify the IdentityHub DID endpoint is accessible: `curl http://<host>:7093/<did-path>`
- Check that `edc.iam.did.web.use.https=false` is set (default in the config files)

### Connection refused

- Verify the required ports are open between machines (see ports table above)
- If using a firewall, ensure the ports are allowed
- Test with: `curl http://<remote-host>:19194/protocol` (should return an error response, not connection refused)

### Seed script fails

- Make sure all containers are healthy: `docker ps`
- Wait for IdentityHub to be ready: `curl http://localhost:7090/api/check/health`
- Check that `deployment/assets/issuer_private.pem` exists (run `./generate-keys.sh`)
