# AWS - PILOTS INFRASTRUCTURE SETUP

## What this stack deploys

- ECS Fargate services for `dashboard`, `identityhub`, `controlplane`, and `dataplane`
- ECS Fargate support services mirroring local compose: `postgres`, `vault`, and `did-server`
- Persistent storage for `postgres` using EFS (data survives task/service restarts)
- Demand-based autoscaling (`0..1`) for externally routed dev services to reduce idle cost
- Application Load Balancer with HTTPS and suffix/path routing:
  - `https://<root-domain>/dashboard/...`
  - `https://<root-domain>/credentials/...`
  - `https://<root-domain>/did-api/...`
  - `https://<root-domain>/did-server/...`
  - `https://<root-domain>/dsp/...`
  - `https://<root-domain>/data/...`
- Route53 hosted zone + root alias record to ALB
- ACM certificate for root and wildcard domains

## Prerequisites

### aws-vault

To access AWS through CLI and Terraform, use `aws-vault`.

Create `~/.aws/config`:

```ini
[default]
region = eu-west-3
output = json

[profile pilots]
sso_account_id = <YOUR_AWS_ACCOUNT_ID>
sso_role_name = <YOUR_SSO_ROLE_NAME>
sso_session = <YOUR_SSO_SESSION_NAME>
region = eu-west-3
output = json

[sso-session <YOUR_SSO_SESSION_NAME>]
sso_start_url = https://<YOUR_ACCESS_PORTAL_ID>.awsapps.com/start
sso_region = eu-west-3
sso_registration_scopes = sso:account:access
```

Start a session:

```bash
unset AWS_VAULT && aws-vault exec pilots --no-session
```

### Terraform state management

Prerequisites:
- An S3 bucket for Terraform state
- A DynamoDB table for state locking

```bash
export MY_COMPANY_NAME=my-company
export BUCKET_NAME=${MY_COMPANY_NAME}-pilots-infra-terraform
export DYNAMODB_NAME=${MY_COMPANY_NAME}-pilots-infra-terraform-lock-table
export REGION=eu-west-3

aws s3 mb s3://$BUCKET_NAME --region $REGION
aws s3api put-bucket-versioning --bucket $BUCKET_NAME --versioning-configuration Status=Enabled
aws dynamodb create-table \
    --table-name $DYNAMODB_NAME \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --region $REGION
```

### GHCR access for ECS

ECS must authenticate against GitHub Container Registry to pull private images.

Working option: create a **classic PAT** and store it as pull credentials.

1. In GitHub, go to **Settings -> Developer settings -> Personal access tokens -> Tokens (classic) -> Generate new token (classic)**.
2. Select scopes:
   - `read:packages` (required for GHCR pull)
   - `public_repo` (or `repo` if package visibility requires private repo access)
   - `read:project` (optional, safe to keep if already used by your account workflows)
3. Set a short expiration and generate the token.
4. Store token in AWS Secrets Manager as Docker credentials:

```bash
aws secretsmanager create-secret \
  --name pilots-ghcr-credentials \
  --secret-string '{"username":"<github-username>","password":"<github-token>"}' \
  --region eu-west-3
```

Copy the returned ARN and set `ghcr_credentials_secret_arn` in your tfvars file.

Example:

```hcl
ghcr_credentials_secret_arn = "arn:aws:secretsmanager:eu-west-3:123456789012:secret:pilots-ghcr-credentials-xxxxx"
```

Fine-grained PATs can still be used, but GitHub UI/permission behavior may vary by org settings. Classic PAT with the scopes above is valid for this deployment.

## Environment config

Use `environments/dev.tfvars.example` as base:

```bash
cp environments/dev.tfvars.example environments/dev.tfvars
```

Then update:
- `root_domain`
- `ghcr_credentials_secret_arn`
- optional sizing (`ecs_cpu`, `ecs_memory`)
- optional rollout image tag (`image_tag`)

Dev defaults are intentionally cost-lean (`ecs_cpu=256`, `ecs_memory=512`).

## Applying Terraform config

```bash
terraform init
unset AWS_VAULT && aws-vault exec pilots --no-session
terraform plan -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

### Certificate validation preflight (important)

If ACM stays in `PENDING_VALIDATION`, `terraform apply` can hang for a long time. Before applying, ensure your registrar/DNS provider delegates the root domain to the Route53 nameservers from output `route53_nameservers`.

You can also verify the ACM CNAME records are visible publicly:

```bash
dig CNAME _fc0d5cfaa6e5ecf008e6f38f372145dd.pilots.t-mining.ma-de.be +short
dig CNAME _f640f4eb7b833361535ac9554b42e94f.dev.pilots.t-mining.ma-de.be +short
```

If these records do not resolve from public DNS, ACM validation cannot complete yet.

## GHCR preflight check

Before `terraform apply`, verify that `ghcr_credentials_secret_arn` is set and readable by your current AWS session.

```bash
# 1) Ensure ARN is set in tfvars (non-empty)
rg '^\s*ghcr_credentials_secret_arn\s*=\s*".+"' environments/dev.tfvars

# 2) Export the ARN from tfvars
export GHCR_SECRET_ARN="$(sed -n 's/^\s*ghcr_credentials_secret_arn\s*=\s*"\(.*\)"/\1/p' environments/dev.tfvars)"

# 3) Confirm the secret exists and can be read
aws secretsmanager describe-secret --secret-id "$GHCR_SECRET_ARN" --region eu-west-3 >/dev/null && echo "Secret exists"
aws secretsmanager get-secret-value --secret-id "$GHCR_SECRET_ARN" --region eu-west-3 --query ARN --output text
```

If both commands succeed, ECS can use this secret for GHCR authentication.

## Image rollout behavior

- Default image tag is `latest`.
- ECS services are configured with `force_new_deployment = true`, so a new deployment is triggered on apply.
- To pin/promote specific builds, set `image_tag` in tfvars and run `terraform apply`.

## Scale-to-zero behavior (dev)

- Routed services (`dashboard`, `identityhub`, `controlplane`, `dataplane`, `did-server`) start at `desired_count = 0`.
- Application Auto Scaling increases them to `1` on ALB traffic and scales back to `0` after idle cooldown.
- `postgres` and `vault` stay at `1` to keep dependency startup predictable.
- First request after idle can return a temporary 5xx/timeout while tasks cold-start (expected in this mode).

## Notes / improvements for review

- The old EC2 SSH key, instance bootstrap, and manual docker-compose deployment have been removed from Terraform.
- Runtime config and cert files are injected into containers at startup, but sourced directly from the repository `config/` and `deployment/` files at Terraform plan/apply time.
- This keeps configuration rooted in the existing codebase files and avoids drift between Terraform-only copies and the connector config directory.
- To reduce lock-in, we keep core runtime components containerized (including Postgres and Vault) instead of replacing them with AWS managed data services.
- Service-specific health endpoints may be tuned further once production endpoint behavior is confirmed.
- ACM certificate validation timeout is configured to fail faster (`20m`) so applies do not wait for 75+ minutes when DNS delegation is missing.
