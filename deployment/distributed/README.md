# Distributed Multi-Machine Deployment

Run EDC connectors on separate machines so they communicate over the network instead of a shared Docker network.

## Architecture

Each machine runs a full EDC stack using the same `docker-compose.yml` and port layout. Either machine can act as provider or consumer toward the other.

```
Machine A                                Machine B
+-------------------------------+        +-------------------------------+
| docker-compose.yml            |        | docker-compose.yml            |
|                               |        |                               |
| provider-controlplane  18181  | <----> | provider-controlplane  18181  |
|   mgmt:19193 DSP:19194       |        |   mgmt:19193 DSP:19194       |
|                               |        |                               |
| consumer-controlplane  28181  | <----> | consumer-controlplane  28181  |
|   mgmt:29193 DSP:29194       |        |   mgmt:29193 DSP:29194       |
|                               |        |                               |
| provider-dataplane     38181  | <----> | provider-dataplane     38181  |
|   public:38185               |        |   public:38185               |
+-------------------------------+        +-------------------------------+
```

Both machines run identical services on identical ports. No port conflicts since they're on different hosts. The `-D` JVM flags in the compose file override cross-network properties with `MY_PUBLIC_URL` so the remote machine can reach back.

## How `MY_PUBLIC_URL` Works

EDC connectors exchange callback URLs during negotiation and transfer. In the single-machine `docker-compose.yml`, these URLs use Docker service names (e.g. `http://provider-controlplane:19194`). That only works when both connectors share the same Docker network.

In a distributed setup, the remote machine can't resolve Docker service names. `MY_PUBLIC_URL` is the address that **the other machine** will use to reach **this machine**. It gets injected into the `-D` JVM flags that override callback and public endpoint URLs.

**You must set `MY_PUBLIC_URL` to an address that the remote machine's Docker containers can connect to.** `http://localhost` will NOT work — inside a container, `localhost` refers to the container itself.

## Prerequisites

- Docker and Docker Compose
- Docker images built (`./gradlew dockerize` in the project root)
- Token signing keys generated (see root [README.md](../../README.md#generate-token-signing-keys))
- Both machines must be able to reach each other on ports 19194, 29194, and 38185 (see [Ports That Must Be Reachable](#ports-that-must-be-reachable))

## Choosing `MY_PUBLIC_URL` for Your Network Setup

### Same LAN / Same Network

If both machines are on the same local network (e.g. office WiFi, home network), use each machine's LAN IP address.

Find your LAN IP:

```bash
# Linux
hostname -I | awk '{print $1}'

# macOS
ipconfig getifaddr en0
```

Example: if Machine A's LAN IP is `192.168.1.50`, set `MY_PUBLIC_URL=http://192.168.1.50` in Machine A's `.env`.

Verify connectivity from Machine B:

```bash
curl http://192.168.1.50:19194  # should get a response (even an error is fine — it means the port is reachable)
```

### Different Networks (not directly routable)

If the machines are on different networks (e.g. different offices, home vs cloud, behind NAT), they can't reach each other by LAN IP. You need a tunnel or public IP.

#### Tailscale (recommended)

[Tailscale](https://tailscale.com/) creates a private WireGuard mesh network. Each machine gets a stable IP (e.g. `100.64.x.x`) that works across any network — home, office, cloud, mobile.

1. Install Tailscale on both machines: https://tailscale.com/download
2. Run `tailscale up` on each
3. Get each machine's Tailscale IP:
   ```bash
   tailscale ip -4
   ```
4. Set `MY_PUBLIC_URL=http://<tailscale-ip>` in each machine's `.env`

All ports are automatically reachable between machines with no firewall configuration needed.

Example: if Machine A's Tailscale IP is `100.100.50.1`:
```
# Machine A's .env
MY_PUBLIC_URL=http://100.100.50.1
```

#### WireGuard / VPN

Any VPN that assigns routable IPs works the same way as Tailscale. Use the VPN-assigned IP as `MY_PUBLIC_URL`.

#### Cloud VM with Public IP

If one or both machines are cloud VMs with public IPs, use the public IP directly. Make sure ports 19194, 29194, and 38185 are open in the cloud security group / firewall.

```
MY_PUBLIC_URL=http://203.0.113.42
```

#### ngrok (last resort)

[ngrok](https://ngrok.com/) exposes local ports via public HTTPS URLs. Since each tunnel gets a **different hostname and port**, it doesn't work with the single `MY_PUBLIC_URL` variable. You need to edit the compose file directly.

1. Start a tunnel for each port:
   ```bash
   ngrok http 19194  # provider DSP        -> e.g. https://abc123.ngrok.io
   ngrok http 29194  # consumer DSP        -> e.g. https://def456.ngrok.io
   ngrok http 38185  # data plane public   -> e.g. https://ghi789.ngrok.io
   ```
2. Edit `docker-compose.yml` and replace each `${MY_PUBLIC_URL}:<port>` with the corresponding ngrok URL (no port number — ngrok routes by hostname):
   - `-Dedc.dsp.callback.address=https://abc123.ngrok.io/protocol` (provider CP)
   - `-Dedc.dsp.callback.address=https://def456.ngrok.io/protocol` (consumer CP)
   - `-Dedc.receiver.http.endpoint=https://def456.ngrok.io/protocol` (consumer CP)
   - `-Dedc.dataplane.api.public.baseurl=https://ghi789.ngrok.io/public` (data plane)

ngrok works for quick tests but Tailscale is simpler for ongoing use.

### Single-Machine Testing

To test the distributed compose file on one machine (e.g. to verify the `-D` overrides work), use the Docker bridge gateway IP. This is the IP the host is reachable at from inside Docker containers.

```bash
# Find the Docker bridge gateway IP (usually 172.17.0.1)
ip route | grep docker0 | awk '{print $NF}'
```

```
# .env
MY_PUBLIC_URL=http://172.17.0.1
```

On macOS/Windows with Docker Desktop, use `http://host.docker.internal` instead.

## Quick Start

1. Copy the env file and set your public URL:
   ```bash
   cd deployment/distributed
   cp .env.example .env
   ```

2. Edit `.env` and set `MY_PUBLIC_URL` to this machine's reachable address (see [Choosing MY_PUBLIC_URL](#choosing-my_public_url-for-your-network-setup) above):
   ```properties
   MY_PUBLIC_URL=http://192.168.1.50   # LAN IP, Tailscale IP, public IP, etc.
   ```

3. Start the services:
   ```bash
   docker compose up
   ```

4. Verify health:
   ```bash
   curl http://localhost:18181/api/check/health  # provider CP
   curl http://localhost:28181/api/check/health  # consumer CP
   curl http://localhost:38181/api/check/health  # data plane
   ```

5. Repeat on the second machine with its own `MY_PUBLIC_URL`.

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
