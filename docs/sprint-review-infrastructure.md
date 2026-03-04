# Pilots Dataspace — Infrastructure Overview

## What's Working Today

### Connector Stack (per machine)

Each machine runs a fully self-contained stack:

```
┌─────────────────────────────────────┐
│  Control Plane                      │  Catalog, negotiation, transfer management
│  Data Plane                         │  Actual data transfer (pull & push)
│  Identity Hub (wallet)              │  DID management, VC storage, credential presentation
│  DID Server (nginx)                 │  Serves issuer DID document (public key)
│  Vault                              │  Secret storage (STS keys, client secrets)
│  PostgreSQL                         │  Persistent state for CP, DP, IdentityHub
│  Dashboard                          │  Web UI for connector management
└─────────────────────────────────────┘
```

### Dashboard

Web UI at port 3000 for managing the connector without curl/API calls:

| Page | What it does |
|------|-------------|
| Assets | Create and view data assets |
| Policies | Define access and contract policies |
| Contract Definitions | Link policies to assets |
| Catalog | Browse remote connectors' catalogs — trusted issuers appear as quick-select buttons |
| Negotiations | Track contract negotiation state |
| Transfers | Initiate and monitor data transfers, fetch data via EDR |
| Trusted Issuers | Add/edit/remove trusted issuer DIDs with connector details (DSP endpoint, participant DID) |

### Identity & Trust

| Capability | Status | Detail |
|-----------|--------|--------|
| DID identifiers | Done | Every connector has a `did:web` identity, resolvable over HTTP |
| VC issuance | Done | Each machine signs its own MembershipCredential (EC P-256 / JWT) |
| VC verification | Done | Incoming VCs verified via DID resolution + JWS 2020 signature suite |
| Trust management | Done | Dynamic trusted issuer registry — add/remove via dashboard or REST API, no restart needed |
| Wallet (storage) | Done | IdentityHub stores VCs and presents them on DSP requests |

### Data Exchange

| Flow | Status |
|------|--------|
| Catalog discovery | Done — request any connector's catalog by DID + DSP URL |
| Contract negotiation | Done — automated offer/accept flow via DSP |
| Pull transfer (HttpData-PULL) | Done — consumer fetches data via EDR token |
| Push transfer (HttpData-PUSH) | Done — provider pushes data to consumer endpoint |
| Bidirectional sharing | Done — any machine can be provider or consumer |

### Deployment Options

| Mode | Location | Description |
|------|----------|-------------|
| **Cloud VM (standalone)** | `deployment/connector/` | One self-contained connector per VM, independent keys, cloud-oriented setup |
| Local development | `docker-compose.yml` (root) | 2 participants on one machine, Docker-internal networking |

---

## Networking: How Do Companies Connect?

Each company deploys their connector on a cloud VM (Azure, AWS, GCP) with a public IP. Connectors communicate directly over the internet using the DSP protocol with DCP identity verification.

```
   Company A              Company B              Company C
 (cloud VM with          (cloud VM with          (cloud VM with
  public IP)              public IP)              public IP)
       ↕                      ↕                      ↕
            direct HTTP between all connectors
```

### Required ports (open in cloud firewall/NSG)

| Port | Service | Why |
|------|---------|-----|
| 7091 | IdentityHub Credentials API | VP/VC presentation requests |
| 7093 | IdentityHub DID endpoint | Participant DID document resolution |
| 9876 | DID Server (nginx) | Issuer DID document resolution |
| 19194 | Control Plane DSP | Catalog, negotiation, transfer callbacks |
| 38185 | Data Plane public | Data fetch via EDR token (pull transfers) |

### Onboarding a new company

1. Company deploys connector on a cloud VM with a public IP
2. Company runs `generate-keys.sh` and `seed.sh` to set up identity
3. Company shares three values: **issuer DID**, **DSP endpoint**, **participant DID**
4. Existing participants add the new company via the **Trusted Issuers** page in the dashboard
5. The new company adds existing participants the same way

No config file changes, no restarts needed — trust is managed dynamically at runtime.

### Machines behind NAT (laptops, on-prem)

Bidirectional connectivity is required — even consumers need to be reachable for DID resolution and negotiation callbacks. Options:
- **[Tailscale](https://tailscale.com/)** — private WireGuard mesh, free, no port forwarding
- **Router port forwarding** — forward the required ports, use public IP
- **Deploy to a cloud VM** — avoids NAT issues entirely (recommended)

---

## TODO's

### Participant Onboarding

| Need | Description |
|------|-------------|
| **Registration platform** | Self-service UI where a new participant can request to join the dataspace |
| **Governance approval** | Admin interface to review, approve, or deny participant registrations |
| **Automated VC issuance** | After approval, automatically issue a MembershipCredential to the participant (currently done manually via `seed.sh`) |

> Today: a participant joins by running a script on their machine. There's no request/approval workflow and no central authority managing membership.

### Discovery

| Need | Description |
|------|-------------|
| **Participant registry** | A shared list of all participants in the dataspace (DIDs, names, endpoints) |
| **Federated catalog** | Browse available datasets across all participants without knowing each connector's URL |

> Today: you must know a connector's DID and DSP endpoint URL to interact with it. The trusted issuers list partially solves this (registered issuers appear as quick-select buttons on the catalog page), but there's no automatic way to discover who's in the dataspace.

### Identity & Profiles

| Need | Description |
|------|-------------|
| **Participant profiles** | Metadata beyond the DID — organization name, description, contact, data offerings |
| **Wallet UI** | User-facing interface to view/manage stored credentials |

> Today: participants are just DIDs with a MembershipCredential. Basic metadata (name, organization, email) is stored with trusted issuers, but there's no rich profile system.

### Governance

| Need | Description |
|------|-------------|
| **Participant management UI** | View all members, revoke membership, manage trust |
| **Per-participant access control** | Allow or deny specific participants (currently all-or-nothing via issuer trust) |
| **Credential revocation** | Revoke a VC without restarting connectors |

> Today: trust is managed per-connector via the trusted issuer registry. Adding/removing issuers is dynamic (no restart), but each connector manages its own trust list independently — there's no central governance authority.

---

## Summary

```
                          DONE                          │           TO DO
                                                        │
  ┌──────────────────────────────────────┐              │  ┌──────────────────────────────────────┐
  │  Connector (CP + DP)                 │              │  │  Registration platform               │
  │  Identity Hub (wallet backend)       │              │  │    - Participant self-service        │
  │  DID & VC (issue, store, verify)     │              │  │    - Governance approval             │
  │  Trust anchor (issuer DID server)    │              │  │    - Automated VC issuance           │
  │  Dynamic trust management            │              │  │                                      │
  │    - REST API + dashboard UI         │              │  │  Discovery                           │
  │    - No restart on trust changes     │              │  │    - Participant registry            │
  │  Full data exchange                  │              │  │    - Federated catalog               │
  │    - Catalog, negotiate, transfer    │              │  │                                      │
  │    - Pull & push                     │              │  │  Profiles & governance UI            │
  │    - Bidirectional                   │              │  │    - Participant profiles            │
  │  Dashboard (web UI)                  │              │  │    - Member management               │
  │    - Asset/policy/contract mgmt      │              │  │    - Credential revocation           │
  │    - Catalog quick-select            │              │  └──────────────────────────────────────┘
  │    - Trusted issuer management       │              │
  │  Cloud-ready deployment              │              │
  │                                      │              │
  │  ✓ Infrastructure layer complete     │              │
  └──────────────────────────────────────┘              │
```

**Bottom line:** The infrastructure plumbing works end-to-end — connectors can discover, negotiate, and exchange data across cloud VMs with full DCP identity. Trust management is dynamic via the dashboard. What's next is the user-facing and governance layer on top.
