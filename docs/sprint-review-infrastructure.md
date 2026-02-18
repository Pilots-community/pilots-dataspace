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
└─────────────────────────────────────┘
```

### Identity & Trust

| Capability | Status | Detail |
|-----------|--------|--------|
| DID identifiers | Done | Every connector has a `did:web` identity, resolvable over HTTP |
| VC issuance | Done | Each machine signs its own MembershipCredential (EC P-256 / JWT) |
| VC verification | Done | Incoming VCs verified via DID resolution + JWS 2020 signature suite |
| Trust management | Done | Comma-separated trusted issuer list per connector (`TRUSTED_ISSUER_DIDS`) |
| Wallet (storage) | Done | IdentityHub stores VCs and presents them on DSP requests |

### Data Exchange (fully tested E2E across machines)

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
| Single machine (dev) | `docker-compose.yml` (root) | 2 participants on one machine, Docker-internal networking |
| Distributed (multi-machine, 2 participants per machine) | `deployment/distributed/` | Both participants on each machine, public IPs |
| **Standalone connector (1 per machine)** | `deployment/connector/` | **NEW** — one self-contained connector per machine, independent keys |

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

> Today: you must know a connector's DID and DSP endpoint URL to interact with it. There's no way to discover who's in the dataspace or what data they offer.

### Identity & Profiles

| Need | Description |
|------|-------------|
| **Participant profiles** | Metadata beyond the DID — organization name, description, contact, data offerings |
| **Wallet UI** | User-facing interface to view/manage stored credentials |

> Today: participants are just DIDs with a MembershipCredential. No profile information is stored or displayed.

### Governance

| Need | Description |
|------|-------------|
| **Participant management UI** | View all members, revoke membership, manage trust |
| **Per-participant access control** | Allow or deny specific participants (currently all-or-nothing via issuer trust) |
| **Credential revocation** | Revoke a VC without restarting connectors |

> Today: trust is managed by a static comma-separated list of issuer DIDs. Adding or removing a participant requires editing config and restarting control planes on every machine.

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
  │  Full data exchange                  │              │  │                                      │
  │    - Catalog, negotiate, transfer    │              │  │  Discovery                           │
  │    - Pull & push                     │              │  │    - Participant registry            │
  │    - Bidirectional                   │              │  │    - Federated catalog               │
  │  3 deployment modes                  │              │  │                                      │
  │                                      │              │  │  Profiles & governance UI            │
  │  ✓ Infrastructure layer complete     │              │  │    - Participant profiles            │
  └──────────────────────────────────────┘              │  │    - Member management               │
                                                        │  │    - Credential revocation           │
                                                        │  └──────────────────────────────────────┘
```

**Bottom line:** The infrastructure plumbing works end-to-end — connectors can discover, negotiate, and exchange data across machines with full DCP identity. What's next is the user-facing and governance layer on top.
