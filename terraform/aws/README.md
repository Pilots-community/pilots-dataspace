# Pilots Dataspace — AWS Terraform deployment

Deploys a single-organization EDC connector on AWS (ECS Fargate + RDS + ALB),
mirroring `deployment/connector/` locally. Always-on at smallest sizing
(~$25–40/mo at idle). Scale-to-zero is not used — peer connectors send
unsolicited DSP / credentials / DID requests and need always-reachable
endpoints.

## Architecture

```
                       Route53 hosted zone (root_domain)
                                 │  apex A-alias
                                 ▼
                       ┌───────────────────┐
                       │  Application Load │  multi-port HTTPS, one wildcard
                       │     Balancer      │  cert, one listener per service
                       └────┬──────────────┘
                            │
  443  ─ dashboard          │  9876  ─ did-server (issuer did:web doc)
  7091 ─ identityhub creds  │  19193 ─ controlplane mgmt    [mgmt_cidrs only]
  7092 ─ identityhub idy *  │  19194 ─ controlplane dsp
  7093 ─ identityhub did    │  38185 ─ dataplane public
                            │
                            ▼
       ┌──────────────────────────────────────────────────┐
       │  ECS Fargate cluster — CloudMap "pilots.internal" │
       │                                                  │
       │  vault       did-server      identityhub         │
       │  controlplane                dataplane           │
       │  dashboard                                       │
       │                                                  │
       │  One-shot tasks: db-seeder, seeder               │
       └──────────────────────────┬───────────────────────┘
                                  │
                            RDS Postgres
                       (controlplane / identityhub
                              / dataplane)
```

**Operator-only ports** (443, 7092, 19193) are SG-restricted to
`var.mgmt_cidrs`. Peer-facing ports (7091, 7093, 9876, 19194, 38185) are
world-open: `did:web:${root_domain}%3A7093` resolves to
`https://${root_domain}:7093/.well-known/did.json` via the dedicated ALB
listener, with no path rewriting.

## Layout

```
terraform/aws/
├── versions.tf  backend.tf  providers.tf  variables.tf  locals.tf
├── main.tf      outputs.tf
├── environments/
│   ├── dev.tfvars.example  (committed)
│   └── dev.tfvars          (gitignored — your values)
├── scripts/
│   ├── upload-keys.sh      operator PEM keys → Secrets Manager
│   ├── run-db-seeder.sh    one-shot: CREATE DATABASE identityhub/dataplane
│   ├── seed-aws.sh         identity bootstrap (participant, DID, VC, trusted issuer)
│   ├── validate.sh         reachability + DSP self-loop test
│   └── fetch-logs.sh       CloudWatch tail per service
└── modules/
    ├── network        default VPC + SGs
    ├── edge           ACM + Route53 + ALB + listeners + TGs
    ├── rds            db.t4g.micro + auto-generated password secret
    ├── ecs-cluster    cluster + CloudMap + split exec/task roles + log group
    ├── ecs-service    reusable task def + service abstraction
    ├── vault          dev-mode Vault on Fargate
    ├── did-server     nginx + EFS shared with seeder
    ├── identityhub  controlplane  dataplane  dashboard
    ├── db-seeder      one-shot: psql idempotent CREATE DATABASE
    └── seeder         one-shot: render did.json into EFS
```

Each EDC service module renders its `.properties` file via `templatefile()`
against a `.tftpl` template, stores the rendered content in Secrets Manager,
and injects it as the `$EDC_CONFIG` env var. The container entrypoint writes
the env var to `/app/config/<svc>.properties` then execs the JAR.

## Prerequisites (one-time)

### 1. AWS access

```bash
aws-vault exec pilots --no-session
```

### 2. S3 state backend

If you haven't already:

```bash
export REGION=eu-west-3
export BUCKET=t-mining-pilots-infra-terraform
export DDB=t-mining-pilots-infra-terraform-lock-table

aws s3 mb "s3://${BUCKET}" --region "${REGION}"
aws s3api put-bucket-versioning --bucket "${BUCKET}" --versioning-configuration Status=Enabled
aws dynamodb create-table \
  --table-name "${DDB}" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region "${REGION}"
```

Bucket/table names are wired into `backend.tf`; edit there if you use
different ones.

### 3. Container images — ECR

Connector images are built locally and pushed to ECR in this account.
ECR repos are managed outside Terraform (the script below creates them) so
image iteration is decoupled from infra apply. Pulls from same-account ECR
are authorised automatically via the ECS execution role — no pull-creds
secret needed.

```bash
# One-time: create the 4 ECR repos (pilots/identityhub, pilots/controlplane,
# pilots/dataplane, pilots/dashboard) with a 10-image + 7-day-untagged
# lifecycle policy and scan-on-push.
./scripts/ecr-bootstrap.sh
# Prints the registry URL; paste into environments/dev.tfvars as image_registry.
# (Or leave image_registry = "" — it auto-derives the same value.)

# Every time you change connector code: build locally for linux/amd64 and push.
# Default tag is the short git SHA so each apply gets a unique task-def revision.
./scripts/build-and-push.sh         # uses git SHA as tag
./scripts/build-and-push.sh latest  # explicit tag

# Then bump image_tag in environments/dev.tfvars and:
terraform apply -var-file=environments/dev.tfvars
```

Notes:
- Build platform is `linux/amd64` (matches the default Fargate runtime).
  Override with `BUILD_PLATFORM=linux/arm64 ./scripts/build-and-push.sh`
  if you also set `runtime_platform` on the task definitions to match.
- If you ever need to point back at GHCR or another private registry,
  set `image_registry = "ghcr.io/<org>/<path>"` and provide
  `ghcr_credentials_secret_arn` (a Secrets Manager secret holding
  `{"username":"…","password":"<PAT>"}`).

### 4. Operator keys

Generate the PEM keys locally and upload to Secrets Manager:

```bash
# From repo root
./generate-keys.sh

# From terraform/aws/
./scripts/upload-keys.sh dev
# Copy the three ARNs printed into dev.tfvars
```

## Bootstrap

```bash
cd terraform/aws
cp environments/dev.tfvars.example environments/dev.tfvars   # if needed
# Edit dev.tfvars — fill in root_domain, mgmt_cidrs (your /32), and the 4 secret ARNs

terraform init
terraform apply -var-file=environments/dev.tfvars
```

ACM validation blocks until NS delegation is in place. After the first
apply:

1. **Delegate NS records** from your registrar to the values in the
   `route53_nameservers` output. Re-run `terraform apply` once delegation
   propagates — ACM should validate within a few minutes.

2. **Create the extra Postgres databases:**
   ```bash
   ./scripts/run-db-seeder.sh
   ```
   Verify in CloudWatch (`/ecs/pilots-dev/db-seeder/...`): "Database
   seeding completed successfully!"

3. **Render the issuer DID document into EFS:**
   ```bash
   terraform output -raw seeder_run_command | bash
   ```
   Verify:
   ```bash
   curl https://${ROOT_DOMAIN}:9876/.well-known/did.json
   ```
   `$.id` should match `did:web:${ROOT_DOMAIN}%3A9876`.

4. **Wait for EDC services to settle.** They may restart 1–2 times during
   first boot while waiting for each other (controlplane needs identityhub,
   etc.). ECS retries automatically.

5. **Validate:**
   ```bash
   ./scripts/validate.sh
   ```

6. **Seed identity:**
   ```bash
   ./scripts/seed-aws.sh
   ```
   Creates the participant context, publishes the connector DID, stores the
   STS client secret, stores the membership VC, and registers the local
   issuer as trusted.

7. **Deep validation (DSP self-loop):**
   ```bash
   ./scripts/validate.sh --deep
   ```

## Day-2

| What                                      | How                                              |
| ----------------------------------------- | ------------------------------------------------ |
| Build + push new images                   | `./scripts/build-and-push.sh` (builds linux/amd64, tags with git SHA, pushes to ECR). |
| Roll connector images                     | Bump `image_tag` in dev.tfvars, `terraform apply`. ECS replaces tasks one at a time. |
| Reach the dashboard                       | `https://<root_domain>/` — open to all IPs (mgmt-restriction is a follow-up). |
| **Check "is it up?"**                     | `terraform output -raw cloudwatch_dashboard_url` — opens the CloudWatch dashboard. |
| Read CloudWatch logs                      | `./scripts/fetch-logs.sh 1h services.log`        |
| **Diagnose a broken deployment**          | `./scripts/gather-diagnostics.sh` — dumps task state, stop reasons, target health, logs, secrets state into a tarball. |
| Get the DB password                       | `aws secretsmanager get-secret-value --secret-id $(terraform output -raw db_password_secret_arn) --query SecretString --output text` |
| Get the Vault root token (dev mode)       | `aws secretsmanager get-secret-value --secret-id $(terraform output -raw vault_root_token_secret_arn) --query SecretString --output text` |
| After a Vault container restart (rare)    | Re-run `./scripts/seed-aws.sh` — vault dev mode loses STS client secrets in-memory. |
| Add a new mgmt-CIDR (e.g. coworker's IP)  | Append to `mgmt_cidrs` in dev.tfvars, `terraform apply`. |
| Run ad-hoc psql                           | Run a one-off ECS task with the `postgres:16-alpine` image and the db-password secret, or use a bastion. |

## Caveats / known limitations (first iteration)

- **Vault is dev mode** — in-memory, lost on container restart. Production
  hardening (raft storage + KMS auto-unseal) is a follow-up.
- **No autoscaling** — `desired_count = 1` per service. Bump manually if
  needed; horizontal scaling on DSP/dataplane is safe; controlplane is too
  but DSP callbacks should pin to one for cleanliness.
- **No multi-AZ RDS, no snapshots** — `skip_final_snapshot = true`,
  `backup_retention_period = 0`. Don't run prod against this state file.
- **Health check matchers are permissive (200–499)** — EDC services
  authenticate every endpoint except the `/api/check/health` on the base
  port (which isn't ALB-exposed). The container-level docker healthcheck
  on the base port governs `RUNNING → HEALTHY`; ALB TG health just
  confirms the container is up.
- **Default VPC** — no NAT, public IPs assigned to tasks. A bespoke VPC
  with private subnets + NAT is a follow-up.

## Follow-ups (out of scope for this iteration)

- Prod environment (multi-AZ RDS, deletion protection, snapshots).
- WAFv2 on the ALB (rate-limit + AWS-managed rule sets in front of
  `/mgmt` and `/identity`).
- Mirror GHCR images into ECR; remove the PAT dependency.
- GitHub Actions: `terraform plan` on PR, `apply` on merge via OIDC trust
  to a deploy role.
- Vault hardening (raft + KMS auto-unseal + AppRole auth).
- CloudWatch dashboards + alarms (ALB 5xx, RDS CPU, ECS desired vs running).
- VPC interface endpoints (Secrets Manager, SSM, ECR, Logs) — avoid NAT
  egress costs.
- AWS Backup plan for RDS + EFS.
- Documented issuer-key rotation runbook.
