# AWS - PILOTS INFRASTRUCTURE SETUP

## What this stack deploys

- ECS Fargate services for `dashboard`, `identityhub`, `controlplane`, and `dataplane`
- ECS Fargate support service: `vault` and `did-server`
- Managed AWS RDS (PostgreSQL) for all databases (Control Plane, Data Plane, IdentityHub)
- Secure credential management using **AWS Secrets Manager** for database passwords
- Permanent ECS Fargate tasks (Desired count = 1) for all services to ensure fast response times
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
- RDS credentials (`db_username`, `db_password`)

Dev defaults are intentionally cost-lean (`ecs_cpu=256`, `ecs_memory=512`, `db_instance_class=db.t4g.micro`).

## Applying Terraform config

```bash
terraform init
unset AWS_VAULT && aws-vault exec pilots --no-session
terraform plan -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

### Certificate validation preflight (important)

If ACM stays in `PENDING_VALIDATION`, `terraform apply` can hang for a long time. Before applying, ensure your registrar/DNS provider delegates the root domain to the Route53 nameservers from output `route53_nameservers`.

### Database Initialization

RDS is initialized with a default `controlplane` database. However, the `identityhub` and `dataplane` databases must be created manually before the services can fully start (or they will retry).

Once RDS is up, you can retrieve the password from Secrets Manager and run the following command from the project root (requires `psql` locally and network access to RDS):

```bash
# Get RDS Endpoint and Secret
export RDS_HOST=<rds-endpoint-host>
export PGPASSWORD=$(aws secretsmanager get-secret-value --secret-id pilots-connector-db-password-dev --region eu-west-3 --query SecretString --output text)
psql -h $RDS_HOST -U edc -d controlplane -f config/docker/postgres-connector-init.sql
```

Note: If RDS is not publicly accessible (default), you may need to run this from a machine within the VPC or use a temporary ECS task.

## Seeding the environment

Once the infrastructure is deployed and DNS is resolving, you must seed the IdentityHub and Control Plane with initial data.

1.  **Ensure DNS is resolving**: Run `./validate.sh` and verify that the domain resolves and HTTPS is working.
2.  **Run the seed script**:
    ```bash
    chmod +x seed-aws.sh
    ./seed-aws.sh
    ```

This script will:
- Create the participant context in **IdentityHub**.
- Activate the context and publish the **Connector DID**.
- Store the **STS Client Secret** in the Control Plane vault.
- Register the **Local Issuer** in the Control Plane so it trusts its own credentials.

## Security Considerations

The `/identity` and `/mgmt` APIs are currently exposed on the Application Load Balancer to allow for remote seeding. In a production environment, you should:
- Restrict these paths to your management IP address in `ssl-routing.tf`.
- Or use a Bastion host/VPN to reach these APIs internally.
- Use a strong `db_password` and do not commit it to the repository.
