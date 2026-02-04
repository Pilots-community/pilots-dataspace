# Tailscale Multi-Machine Setup

Step-by-step guide to run the dataspace across two machines using [Tailscale](https://tailscale.com/) as the network layer. Uses DCP identity with did:web DIDs and Verifiable Credentials.

## Overview

Each machine runs the full EDC stack (IdentityHub + provider + consumer + data plane + vault + did-server + postgres). Tailscale creates a WireGuard mesh so the machines can reach each other without firewall configuration or port forwarding.

```
Machine A (100.x.x.x)                    Machine B (100.x.x.x)
+----------------------------+            +----------------------------+
| provider-identityhub 7090+ |            | provider-identityhub 7090+ |
| consumer-identityhub 7080+ |            | consumer-identityhub 7080+ |
| provider-controlplane      |            | provider-controlplane      |
|   DSP: 19194               | <-------->  |   DSP: 19194               |
| consumer-controlplane      |  Tailscale | consumer-controlplane      |
|   DSP: 29194               | <-------->  |   DSP: 29194               |
| provider-dataplane         |  WireGuard | provider-dataplane         |
|   public: 38185            | <-------->  |   public: 38185            |
| did-server: 9876           |            | did-server: 9876           |
| vault: 8200                |            | vault: 8200                |
+----------------------------+            +----------------------------+
```

## Prerequisites

- Docker and Docker Compose
- Docker images built (`./gradlew dockerize` from project root) -- needs `controlplane`, `dataplane`, and `identityhub`
- Python 3 with the `cryptography` library (for VC generation in seed.sh)
- Issuer private key at `deployment/assets/issuer_private.pem`

## Setup (per machine)

### 1. Install Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

### 2. Connect to your Tailscale network

```bash
sudo tailscale up
```

Follow the authentication link. Both machines must be on the same Tailscale network.

### 3. Get your Tailscale IP

```bash
tailscale ip -4
```

Returns an IP like `100.113.174.98`.

### 4. Start the services

```bash
cd deployment/distributed
MY_PUBLIC_HOST=100.113.174.98 docker compose up -d
```

### 5. Seed identity data

```bash
MY_PUBLIC_HOST=100.113.174.98 ./seed.sh
```

This creates participant contexts, generates DID documents, issues Verifiable Credentials, and updates the issuer DID document -- all using the Tailscale IP for DIDs and service endpoints.

### 6. Verify health

```bash
curl http://localhost:18181/api/check/health   # provider CP
curl http://localhost:28181/api/check/health   # consumer CP
curl http://localhost:38181/api/check/health   # data plane
curl http://localhost:7090/api/check/health    # provider IH
curl http://localhost:7080/api/check/health    # consumer IH
```

### 7. Repeat on the second machine

Install Tailscale, use its own Tailscale IP for `MY_PUBLIC_HOST`, start services, and run seed.sh.

## Transferring Docker Images

If the second machine doesn't have the source code:

```bash
# On the build machine
docker save controlplane:latest dataplane:latest identityhub:latest | gzip > edc-images.tar.gz

# Copy to the other machine
scp edc-images.tar.gz user@<tailscale-ip>:~/

# On the other machine
docker load < edc-images.tar.gz
```

## E2E Test

See [TAILSCALE-E2E-TEST.md](TAILSCALE-E2E-TEST.md) for the full step-by-step E2E flow, or [README.md](README.md) for the general distributed E2E instructions.

## Single-Machine Testing

You can test on one machine -- traffic goes out through the Tailscale interface and back in through Docker port mapping, exercising the same network path as a real multi-machine setup.

```bash
MY_PUBLIC_HOST=$(tailscale ip -4) docker compose up -d
MY_PUBLIC_HOST=$(tailscale ip -4) ./seed.sh
```

Alternatively, without Tailscale, use the Docker bridge gateway IP:

```bash
BRIDGE_IP=$(ip addr show docker0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
MY_PUBLIC_HOST=$BRIDGE_IP docker compose up -d
MY_PUBLIC_HOST=$BRIDGE_IP ./seed.sh
```
