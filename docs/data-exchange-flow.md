# Data Exchange — How It Works

Data exchange has three phases: **catalog discovery**, **contract negotiation**, and **data transfer**. Each phase uses DSP (Dataspace Protocol) over HTTP and is authenticated via DCP (see [identity-flow.md](identity-flow.md)).

---

## Component Roles

```
┌──────────────────────────────────────────────────────────────┐
│                  Control Plane (19193 / 19194)                │
│                                                              │
│  Management API (19193)          DSP Protocol (19194)        │
│  ┌────────────────────────┐      ┌─────────────────────────┐ │
│  │ Your commands:          │      │ Machine-to-machine:      │ │
│  │  - create asset         │      │  - catalog exchange      │ │
│  │  - create policy        │      │  - negotiation messages  │ │
│  │  - start negotiation    │      │  - transfer coordination │ │
│  │  - start transfer       │      │  - callbacks             │ │
│  │  - get EDR              │      │                          │ │
│  └────────────────────────┘      └─────────────────────────┘ │
│                                                              │
│  Stores: assets, policies, contract definitions,             │
│          agreements, transfer process state                   │
│          (all in PostgreSQL)                                  │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                  Data Plane (38181 / 38185)                   │
│                                                              │
│  Control API (38182)             Public API (38185)          │
│  ┌────────────────────────┐      ┌─────────────────────────┐ │
│  │ From Control Plane:     │      │ Consumer fetches here:   │ │
│  │  - "prepare source X"  │      │  - GET /public           │ │
│  │  - "push data to Y"    │      │  - Authorization: Bearer │ │
│  └────────────────────────┘      │    <EDR token>           │ │
│                                  └─────────────────────────┘ │
│                                                              │
│  Pull: serves data via public API with token auth            │
│  Push: fetches from source, POSTs to destination             │
│  Token keys: config/certs/private-key.pem (sign EDR)         │
│              config/certs/public-key.pem (verify EDR)        │
└──────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Catalog Discovery

The consumer asks: "What data do you have, and under what terms?"

```
Consumer                                                Provider
────────                                                ────────

┌──────────────┐                                  ┌──────────────┐
│ Control Plane│                                  │ Control Plane│
└──────┬───────┘                                  └──────┬───────┘
       │                                                 │
  POST /management/v3/catalog/request                    │
  body: { counterPartyAddress,                           │
          counterPartyId }                               │
       │                                                 │
       │                                                 │
 ── DCP authentication ─────────────────────────────────────────────
       │                                                 │
       │  (SI token, credential exchange,                │
       │   VC verification — see identity-flow.md)       │
       │                                                 │
       │                                                 │
 ── Catalog exchange ───────────────────────────────────────────────
       │                                                 │
       │  DSP: POST /protocol/catalog/request            │
       │────────────────────────────────────────────────>│
       │                                                 │
       │                                          Query internal store:
       │                                           - assets
       │                                           - policy definitions
       │                                           - contract definitions
       │                                                 │
       │                                          Build DCAT catalog:
       │                                           - each asset
       │                                             → dcat:dataset
       │                                           - each contract def
       │                                             → odrl:hasPolicy
       │                                                 │
       │              DCAT catalog response               │
       │<────────────────────────────────────────────────│
       │                                                 │
```

The catalog response contains **datasets** (assets) with **policies** (offers). The offer `@id` from `odrl:hasPolicy` is what you need for negotiation.

### What the Provider Set Up Beforehand

```
Provider runs three commands via Management API (19193):

  1. Create Asset                    "I have this data"
     ┌─────────────────────────────────────────────────┐
     │ @id: "sample-asset-1"                           │
     │ properties: { name, contenttype }               │
     │ dataAddress: {                                  │
     │   type: "HttpData"                              │
     │   baseUrl: "https://example.com/api/data"  ◄──── where the actual data lives
     │ }                                               │
     └─────────────────────────────────────────────────┘

  2. Create Policy Definition        "Under these terms"
     ┌─────────────────────────────────────────────────┐
     │ @id: "open-policy"                              │
     │ policy: {                                       │
     │   permission: []    ◄──── open access (no       │
     │   prohibition: []        constraints beyond     │
     │   obligation: []         MembershipCredential)  │
     │ }                                               │
     └─────────────────────────────────────────────────┘

  3. Create Contract Definition      "Link assets to terms"
     ┌─────────────────────────────────────────────────┐
     │ @id: "sample-contract-def"                      │
     │ accessPolicyId: "open-policy"                   │
     │ contractPolicyId: "open-policy"                 │
     │ assetsSelector: []  ◄──── empty = all assets    │
     └─────────────────────────────────────────────────┘
```

---

## Phase 2: Contract Negotiation

The consumer says: "I want asset X under offer Y." This is an asynchronous state machine with DSP callbacks between both Control Planes.

```
Consumer CP                                              Provider CP
───────────                                              ───────────

POST /management/v3/contractnegotiations
body: { counterPartyAddress, counterPartyId,
        policy: { @id: <OFFER_ID>,
                  target: <ASSET_ID>,
                  assigner: <PROVIDER_DID> } }
       │
       │
 ── Request ────────────────────────────────────────────────────────
       │
  State: REQUESTING
       │
       │  DSP: POST /protocol/negotiations/request
       │────────────────────────────────────────────────────────>│
       │                                                         │
       │                                                  Validate offer:
       │                                                   - Does asset exist?
       │                                                   - Does policy match?
       │                                                   - Is consumer allowed?
       │                                                         │
       │                                                         │
 ── Agreement ──────────────────────────────────────────────────────
       │                                                         │
       │                                                  State: AGREEING
       │                                                         │
       │  DSP: POST /protocol/negotiations/agreement             │
       │<────────────────────────────────────────────────────────│
       │                                                         │
  State: AGREED                                                  │
       │                                                         │
       │                                                         │
 ── Verification ───────────────────────────────────────────────────
       │                                                         │
       │  DSP: POST /protocol/negotiations/verification          │
       │────────────────────────────────────────────────────────>│
       │                                                         │
       │                                                  State: FINALIZED
       │                                                         │
       │                                                         │
 ── Finalized ──────────────────────────────────────────────────────
       │                                                         │
       │  DSP: POST /protocol/negotiations/finalized             │
       │<────────────────────────────────────────────────────────│
       │                                                         │
  State: FINALIZED                                               │
  contractAgreementId = <AGREEMENT_ID>                           │
       │                                                         │
```

The agreement ID is the "receipt" proving both parties agreed on terms. You poll `GET /management/v3/contractnegotiations/<ID>` until `state` = `FINALIZED`, then extract the `contractAgreementId`.

Each DSP callback goes through DCP authentication — both sides verify identity on every message.

---

## Phase 3a: Pull Transfer (HttpData-PULL)

The consumer asks the provider to prepare data for download. The consumer then fetches directly from the provider's **Data Plane**.

```
Consumer CP                 Provider CP                  Provider DP
───────────                 ───────────                  ───────────

POST /management/v3/
  transferprocesses
body: { contractId,
        assetId,
        transferType:
          "HttpData-PULL" }
       │
       │
 ── Transfer request ───────────────────────────────────────────────
       │
  State: REQUESTING
       │
       │  DSP: POST /protocol/transfers/request
       │──────────────────────────────────────>│
       │                                       │
       │                                 Validate contract:
       │                                  - Agreement exists?
       │                                  - Asset matches?
       │                                       │
       │                                       │
 ── Data Plane preparation ─────────────────────────────────────────
       │                                       │
       │                                 Tell Data Plane:
       │                                 "prepare source
       │                                  for asset X"
       │                                       │──────────────>│
       │                                       │               │
       │                                 Create EDR:           │
       │                                  - endpoint URL       │
       │                                  - auth token         │
       │                                    (JWT signed with   │
       │                                     DP private key)   │
       │                                       │               │
       │                                       │               │
 ── EDR delivery ───────────────────────────────────────────────────
       │                                       │               │
       │  DSP: POST /transfers/start           │               │
       │  (includes EDR)                       │               │
       │<──────────────────────────────────────│               │
       │                                       │               │
  State: STARTED                               │               │
  EDR stored locally                           │               │
       │                                       │               │
       │                                       │               │
 ── Data fetch (consumer → provider Data Plane) ────────────────────
       │                                       │               │
  GET /management/v3/edrs/                     │               │
    <TRANSFER_ID>/dataaddress                  │               │
  → { endpoint, authorization }                │               │
       │                                       │               │
       │  GET <endpoint>                       │               │
       │  Authorization: Bearer <token>        │               │
       │─────────────────────────────────────────────────────>│
       │                                       │               │
       │                                       │         Verify token
       │                                       │         (DP public key)
       │                                       │               │
       │                                       │         Fetch from
       │                                       │         data source
       │                                       │         (asset's
       │                                       │          baseUrl)
       │                                       │               │
       │                 actual data            │               │
       │<─────────────────────────────────────────────────────│
       │                                       │               │
```

### The EDR (Endpoint Data Reference)

```
┌─ EDR ──────────────────────────────────────────────────────────┐
│                                                                │
│  endpoint:      http://<provider-host>:38185/public            │
│                          ▲                                     │
│                          │                                     │
│                 Provider Data Plane's public API               │
│                                                                │
│  authorization: <JWT token>                                    │
│                     │                                          │
│                     ▼                                          │
│          ┌─────────────────────────────────┐                   │
│          │ Signed with: DP private key     │                   │
│          │   (config/certs/private-key.pem)│                   │
│          │ Verified with: DP public key    │                   │
│          │   (config/certs/public-key.pem) │                   │
│          │ Contains: asset ID, agreement   │                   │
│          │   ID, expiration                │                   │
│          └─────────────────────────────────┘                   │
│                                                                │
│  The token proves the consumer has a valid contract            │
│  agreement for this specific asset.                            │
└────────────────────────────────────────────────────────────────┘
```

---

## Phase 3b: Push Transfer (HttpData-PUSH)

The consumer tells the provider: "Send the data to this URL." The provider's Data Plane fetches the data and delivers it to the consumer's endpoint.

```
Consumer CP                 Provider CP                  Provider DP
───────────                 ───────────                  ───────────

POST /management/v3/
  transferprocesses                          ┌────────────────────┐
body: { contractId,                          │ Consumer also runs │
        assetId,                             │ an http-receiver   │
        transferType:                        │ on port 4000       │
          "HttpData-PUSH",                   └────────────────────┘
        dataDestination: {
          type: "HttpData",
          baseUrl: "http://
            <consumer>:4000/"
        }}
       │
       │
 ── Transfer request ───────────────────────────────────────────────
       │
  State: REQUESTING
       │
       │  DSP: POST /protocol/transfers/request
       │──────────────────────────────────────>│
       │                                       │
       │                                 Validate contract
       │                                       │
       │                                       │
 ── Data Plane pushes data ─────────────────────────────────────────
       │                                       │
       │                                 Tell Data Plane:
       │                                 "fetch from source,
       │                                  push to destination"
       │                                       │──────────────>│
       │                                       │               │
       │                                       │         Fetch data
       │                                       │         from source
       │                                       │         (asset's
       │                                       │          baseUrl)
       │                                       │               │
       │                                       │               │
 ── Data delivery ──────────────────────────────────────────────────
       │                                       │               │
       │                                       │         POST data to
       │                                       │         consumer's
       │                                       │         destination
       │                                       │               │
  http-receiver  ◄─────────── POST data ───────────────────────│
  (port 4000)                                  │               │
       │                                       │               │
       │                                       │               │
 ── Completion ─────────────────────────────────────────────────────
       │                                       │               │
       │  DSP: POST /transfers/completion      │               │
       │<──────────────────────────────────────│               │
       │                                       │               │
  State: COMPLETED                             │               │
       │                                       │               │
```

### Pull vs Push

| | Pull (HttpData-PULL) | Push (HttpData-PUSH) |
|---|---|---|
| **Who fetches data** | Consumer, via EDR token | Provider's Data Plane |
| **Who delivers data** | Provider's Data Plane serves it | Provider's Data Plane POSTs it |
| **Consumer needs** | EDR endpoint + token | A reachable HTTP endpoint |
| **Final state** | `STARTED` (consumer can fetch repeatedly) | `COMPLETED` (one-time delivery) |
| **Token involved** | EDR JWT (DP key pair) | None for delivery |
| **Consumer port** | None (consumer calls out) | 4000 (http-receiver, or any HTTP server) |

---

## Full End-to-End Sequence

```
Provider                                                    Consumer
────────                                                    ────────

 1. Create asset
    (name, data source URL)

 2. Create policy
    (access rules)

 3. Create contract definition
    (links assets to policy)

                              ◄── 4. Request catalog ────────
                                   (DCP auth)
    Return DCAT catalog ──────────────────────────────────►

                              ◄── 5. Negotiate contract ─────
                                   (offer ID + asset ID)
    Validate, agree ──────────────────────────────────────►
    ◄── Verify ───────────────────────────────────────────
    Finalize ─────────────────────────────────────────────►
                                   contractAgreementId ✓

                              ◄── 6. Start transfer ─────────
                                   (agreement ID + type)

    ┌─────── PULL ──────┐     ┌─────── PUSH ──────────┐
    │                    │     │                        │
    │ Prepare DP,        │     │ DP fetches data,      │
    │ send EDR to        │     │ POSTs to consumer's   │
    │ consumer           │     │ destination URL        │
    │                    │     │                        │
    │ Consumer fetches   │     │ Transfer completes     │
    │ from DP public API │     │ automatically          │
    │ using EDR token    │     │                        │
    └────────────────────┘     └────────────────────────┘

                                   7. Data received ✓
```

---

## Three Sets of Keys

Each machine has three independent key pairs used at different stages:

```
┌─ Identity (DCP authentication) ──────────────────────────────────┐
│                                                                  │
│  Participant key (Ed25519)         Issuer key (EC P-256)         │
│  ┌──────────────────────────┐      ┌──────────────────────────┐  │
│  │ Generated by:             │      │ Generated by:             │  │
│  │   Identity Hub            │      │   generate-keys.sh        │  │
│  │ Stored in: Vault          │      │ Stored in:                │  │
│  │ Signs: SI tokens          │      │   deployment/assets/      │  │
│  │ Verified via:             │      │ Signs: MembershipCred     │  │
│  │   did:web:host%3A7093     │      │ Verified via:             │  │
│  │                           │      │   did:web:host%3A9876     │  │
│  │ "Who I am in DSP"        │      │ "I'm a trusted member"   │  │
│  └──────────────────────────┘      └──────────────────────────┘  │
│                                                                  │
│  Used in: catalog, negotiation, transfer (every DSP message)     │
└──────────────────────────────────────────────────────────────────┘

┌─ Data access (transfer phase only) ──────────────────────────────┐
│                                                                  │
│  Data Plane token key (configurable)                             │
│  ┌──────────────────────────┐                                    │
│  │ Generated by:             │                                    │
│  │   generate-keys.sh        │                                    │
│  │ Stored in: config/certs/  │                                    │
│  │ Signs: EDR tokens         │                                    │
│  │   (private-key.pem)       │                                    │
│  │ Verifies: EDR tokens      │                                    │
│  │   (public-key.pem)        │                                    │
│  │                           │                                    │
│  │ "Consumer can fetch       │                                    │
│  │  this specific asset"     │                                    │
│  └──────────────────────────┘                                    │
│                                                                  │
│  Used in: pull transfers only (EDR token for data fetch)         │
└──────────────────────────────────────────────────────────────────┘
```

| Key pair | Type | Where | What it does |
|---|---|---|---|
| Participant key | Ed25519 | Identity Hub / Vault | Signs SI tokens for DSP authentication |
| Issuer key | EC P-256 | `deployment/assets/` / nginx | Signs MembershipCredentials (VCs) |
| Data Plane token key | PEM | `config/certs/` | Signs/verifies EDR tokens for pull data fetch |

---

## Ports Used in Data Exchange

| Port | Service | Role in data exchange |
|---|---|---|
| 19193 | CP Management API | Your commands: create assets, start negotiations, get EDRs |
| 19194 | CP DSP Protocol | Machine-to-machine: catalog, negotiation, transfer messages |
| 19192 | CP Control API | Internal: CP tells DP to register as data plane |
| 38182 | DP Control API | Internal: CP tells DP to prepare/push data |
| 38185 | DP Public API | Consumer fetches data here (pull transfers) |
| 4000 | http-receiver | Test endpoint for push transfers |
