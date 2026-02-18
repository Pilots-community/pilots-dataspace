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

## Networking: How Do Companies Connect?

Different companies need to reach each other's connectors on specific ports (7093, 9876, 19194, 38185). Two realistic approaches:

### Option A: Nebula (self-hosted mesh VPN)

Pilots runs a lightweight **lighthouse** server on a cheap VPS. Each company installs the Nebula agent and receives a certificate from Pilots to join. Traffic flows directly between companies (peer-to-peer), not through the lighthouse.

```
              Pilots (governance)
              runs lighthouse + CA
             /        |         \
            /         |          \
     Company A    Company B    Company C
     (cert A)     (cert B)     (cert C)
         ↕            ↕            ↕
      direct P2P traffic between all
```

**Onboarding a new company:**
1. Company requests to join
2. Pilots issues a Nebula certificate (= governance approval)
3. Company installs Nebula agent + certificate
4. Company can now reach all other participants — no change needed on existing machines

**Pros:** Pilots controls who joins (issue cert = approve, revoke cert = deny). Open source, no vendor dependency. Certificate model mirrors the VC trust model. Adding participant N doesn't touch participants 1 through N-1.

**Cons:** Each company needs to install software and open one UDP port.

### Option B: Public endpoints (no VPN)

Each company exposes the required ports directly on a public IP or behind a reverse proxy with TLS. No VPN needed — connectors talk over the public internet.

```
     Company A              Company B              Company C
   (public IP or           (public IP or           (public IP or
    reverse proxy)          reverse proxy)          reverse proxy)
         ↕                      ↕                      ↕
              direct HTTPS between all
```

**Onboarding a new company:**
1. Company deploys connector with a public IP or sets up a reverse proxy
2. Company shares their hostname with Pilots
3. Pilots adds them to the trusted issuer list
4. All existing participants update `TRUSTED_ISSUER_DIDS` and restart control plane

**Pros:** No extra software — just Docker. Companies are used to exposing web services. Works with existing corporate infrastructure.

**Cons:** Each company needs a public IP or domain + TLS certificates. Updating every participant's config when someone joins gets painful at scale.

### Comparison

| | Nebula (mesh VPN) | Public endpoints |
|---|---|---|
| **Barrier for companies** | Install Nebula agent | Expose ports / set up reverse proxy |
| **IT department friction** | "Install this VPN" — might get pushback | "Open these ports" — more familiar |
| **Governance control** | Strong — revoke cert = kick out | Weaker — remove from issuer list + restart everyone |
| **Adding participant N** | Just issue a cert, zero change for others | Update config + restart control plane on every machine |
| **Security** | Encrypted tunnel, not exposed to internet | Exposed ports, relies on TLS + DCP auth |
| **Scales to 10+** | Well | `TRUSTED_ISSUER_DIDS` restart problem needs solving |

> **Key question for discussion:** Which friction is more acceptable to target companies — installing a VPN agent, or exposing ports to the internet?
>
> **Scaling note:** With either option, the current `TRUSTED_ISSUER_DIDS` mechanism (static list, requires restart) becomes painful beyond ~5 participants. A shared participant registry that connectors poll would solve this but is a bigger piece of work.

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
