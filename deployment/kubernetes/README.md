# Deploying Pilots Dataspace to Azure Kubernetes Service (AKS)

This guide walks you through deploying the Pilots Dataspace application to Azure Kubernetes Service (AKS) using Azure Container Registry (ACR).

## Prerequisites

- Azure CLI installed and configured (`az` command)
- Docker installed
- Java 17+ (for building the application)
- `kubectl` configured to connect to your AKS cluster
- An Azure Container Registry (ACR) - Example: `pilotsdataspaceregistry`
- An Azure Kubernetes Service (AKS) cluster

## Architecture

The deployment consists of the following components:

1. **PostgreSQL** - Shared database for all components
2. **HashiCorp Vault** - Secret management (dev mode)
3. **DID Server** - NGINX server hosting DID documents
4. **Provider IdentityHub** - Identity management for provider
5. **Consumer IdentityHub** - Identity management for consumer
6. **Provider Control Plane** - Control plane for provider
7. **Consumer Control Plane** - Control plane for consumer
8. **Provider Data Plane** - Data plane for provider
9. **Consumer Data Plane** - Data plane for consumer

## Step 1: Connect AKS to ACR

Ensure your AKS cluster has permission to pull images from your ACR:

```bash
# Get your AKS and ACR names
AKS_NAME="your-aks-cluster-name"
ACR_NAME="pilotsdataspaceregistry"
RESOURCE_GROUP="your-resource-group"

# Attach ACR to AKS
az aks update -n $AKS_NAME -g $RESOURCE_GROUP --attach-acr $ACR_NAME
```

## Step 2: Generate Keys and Credentials

Before building, generate the necessary keys and DID documents:

```bash
cd ~/pilots-dataspace
./generate-keys.sh
```

This creates:
- Private keys for each component
- DID documents in `deployment/assets/issuer/`
- Verifiable credentials

## Step 3: Build and Push Docker Images to ACR

### Option A: Using PowerShell (Windows)

```powershell
cd <repo-root>\deployment\kubernetes
.\build-and-push-to-acr.ps1 -AcrName "pilotsdataspaceregistry"
```

### Option B: Using Bash (WSL/Linux/Mac)

```bash
cd ~/pilots-dataspace/deployment/kubernetes
chmod +x build-and-push-to-acr.sh
./build-and-push-to-acr.sh pilotsdataspaceregistry
```

This script will:
1. Build the Java applications using Gradle
2. Build Docker images for IdentityHub, Control Plane, and Data Plane
3. Push the custom images to ACR
4. Import base images (postgres, nginx, vault, python) to ACR

## Step 4: Create Required Secrets and ConfigMaps

### Create Kubernetes Secret (required)

Create the `pilots-dataspace-secrets` secret in your cluster. Do not commit real values.

Option A: apply a local `02-secrets.yaml` (recommended)

```bash
cd deployment/kubernetes
# Copy the template and fill in values locally
cp 02-secrets.example.yaml 02-secrets.yaml
kubectl apply -f 02-secrets.yaml
```

Option B: create from literals

```bash
kubectl create secret generic pilots-dataspace-secrets \
   -n pilots-dataspace \
   --from-literal=postgres-user=edc \
   --from-literal=postgres-password='<REPLACE_ME>' \
   --from-literal=vault-token='<REPLACE_ME>' \
   --from-literal=api-auth-key='<REPLACE_ME>' \
   --from-literal=superuser-token='<REPLACE_ME>'
```

### Create DID JSON ConfigMap

First, create a ConfigMap with your generated DID document:

```bash
kubectl create configmap did-json \
  --from-file=did.json=deployment/assets/issuer/did.json \
  -n pilots-dataspace
```

### Create Dataplane Certificates Secret

Create certificates for the dataplane:

```bash
# If you don't have certificates, generate them:
mkdir -p config/certs
openssl genrsa -out config/certs/private-key.pem 2048
openssl rsa -in config/certs/private-key.pem -pubout -out config/certs/public-key.pem

# Create the secret
kubectl create secret generic dataplane-certs \
  --from-file=private-key.pem=config/certs/private-key.pem \
  --from-file=public-key.pem=config/certs/public-key.pem \
  -n pilots-dataspace
```

## Step 5: Deploy to Kubernetes

Deploy all components in order:

```bash
cd deployment/kubernetes

# 1. Create namespace
kubectl apply -f 00-namespace.yaml

# 2. Create configmaps for postgres init
kubectl apply -f 01-configmap-postgres.yaml

# 3. Create secrets
kubectl get secret pilots-dataspace-secrets -n pilots-dataspace

# 4. Deploy infrastructure components
kubectl apply -f 03-postgres.yaml
kubectl apply -f 04-vault.yaml
kubectl apply -f 05-did-server.yaml

# Wait for infrastructure to be ready
kubectl wait --for=condition=ready pod -l app=postgres -n pilots-dataspace --timeout=120s
kubectl wait --for=condition=ready pod -l app=vault -n pilots-dataspace --timeout=120s
kubectl wait --for=condition=ready pod -l app=did-server -n pilots-dataspace --timeout=120s

# 5. Deploy IdentityHub components
kubectl apply -f 06-identityhub.yaml

# Wait for IdentityHub to be ready
kubectl wait --for=condition=ready pod -l app=provider-identityhub -n pilots-dataspace --timeout=180s
kubectl wait --for=condition=ready pod -l app=consumer-identityhub -n pilots-dataspace --timeout=180s

# 6. Deploy Control Plane components
kubectl apply -f 07-controlplane.yaml

# Wait for Control Plane to be ready
kubectl wait --for=condition=ready pod -l app=provider-controlplane -n pilots-dataspace --timeout=180s
kubectl wait --for=condition=ready pod -l app=consumer-controlplane -n pilots-dataspace --timeout=180s

# 7. Deploy Data Plane components
kubectl apply -f 08-dataplane.yaml

# Wait for Data Plane to be ready
kubectl wait --for=condition=ready pod -l app=provider-dataplane -n pilots-dataspace --timeout=180s
kubectl wait --for=condition=ready pod -l app=consumer-dataplane -n pilots-dataspace --timeout=180s
```

## Step 6: Verify Deployment

Check that all pods are running:

```bash
kubectl get pods -n pilots-dataspace
```

Expected output:
```
NAME                                      READY   STATUS    RESTARTS   AGE
consumer-controlplane-xxxxx               1/1     Running   0          2m
consumer-dataplane-xxxxx                  1/1     Running   0          1m
consumer-identityhub-xxxxx                1/1     Running   0          3m
did-server-xxxxx                          1/1     Running   0          5m
postgres-xxxxx                            1/1     Running   0          5m
provider-controlplane-xxxxx               1/1     Running   0          2m
provider-dataplane-xxxxx                  1/1     Running   0          1m
provider-identityhub-xxxxx                1/1     Running   0          3m
vault-xxxxx                               1/1     Running   0          5m
```

Check services:

```bash
kubectl get svc -n pilots-dataspace
```

## Step 7: Access the Services

### Port Forward for Local Access

To access the management APIs locally:

```bash
# Provider Control Plane Management API
kubectl port-forward -n pilots-dataspace svc/provider-controlplane 19193:19193

# Consumer Control Plane Management API
kubectl port-forward -n pilots-dataspace svc/consumer-controlplane 29193:29193

# Provider IdentityHub
kubectl port-forward -n pilots-dataspace svc/provider-identityhub 7090:7090

# Consumer IdentityHub
kubectl port-forward -n pilots-dataspace svc/consumer-identityhub 7080:7080
```

### Expose via LoadBalancer (Optional)

To expose services externally, you can modify the Service type from `ClusterIP` to `LoadBalancer` for specific services:

```bash
kubectl patch svc provider-controlplane -n pilots-dataspace -p '{"spec": {"type": "LoadBalancer"}}'
kubectl patch svc consumer-controlplane -n pilots-dataspace -p '{"spec": {"type": "LoadBalancer"}}'
```

## Step 8: Seed Initial Data

If you need to seed initial data (credentials, participants), you can run the seed script:

```bash
# Port forward first
kubectl port-forward -n pilots-dataspace svc/provider-identityhub 7090:7090 &
kubectl port-forward -n pilots-dataspace svc/consumer-identityhub 7080:7080 &

# Run seed script (from your local machine)
cd ~/pilots-dataspace/deployment
./seed.sh
```

## Step 9: Test the Deployment

Run a health check on the management endpoints:

```bash
# Provider Control Plane
curl http://localhost:19193/management/check/health

# Consumer Control Plane
curl http://localhost:29193/management/check/health
```

## Updating the Deployment

To update the application after making changes:

1. Rebuild and push images:
   ```powershell
   cd deployment\kubernetes
   .\build-and-push-to-acr.ps1
   ```

2. Restart the deployments:
   ```bash
   kubectl rollout restart deployment -n pilots-dataspace
   ```

## Cleanup

To remove the entire deployment:

```bash
kubectl delete namespace pilots-dataspace
```

## Troubleshooting

### Check Pod Logs

```bash
# View logs for a specific pod
kubectl logs -n pilots-dataspace <pod-name>

# Follow logs
kubectl logs -n pilots-dataspace <pod-name> -f

# Check previous logs if pod crashed
kubectl logs -n pilots-dataspace <pod-name> --previous
```

### Describe Pod for Events

```bash
kubectl describe pod -n pilots-dataspace <pod-name>
```

### Common Issues

1. **ImagePullBackOff**: Ensure AKS is attached to ACR and images exist
   ```bash
   az aks check-acr --name $AKS_NAME --resource-group $RESOURCE_GROUP --acr $ACR_NAME.azurecr.io
   ```

2. **CrashLoopBackOff**: Check pod logs for application errors
   ```bash
   kubectl logs -n pilots-dataspace <pod-name> --previous
   ```

3. **Pods Stuck in Init**: Check if prerequisite services are running
   ```bash
   kubectl get pods -n pilots-dataspace
   kubectl describe pod -n pilots-dataspace <pod-name>
   ```

## Security Considerations

**⚠️ IMPORTANT**: This deployment uses default credentials and is suitable for development/testing only.

For production:

1. **Change all secrets** in `02-secrets.yaml`
2. **Use Azure Key Vault** instead of ConfigMaps/Secrets for sensitive data
3. **Enable HTTPS** for all endpoints
4. **Use managed PostgreSQL** (Azure Database for PostgreSQL) instead of containerized postgres
5. **Configure network policies** to restrict traffic between pods
6. **Enable Azure AD integration** for authentication
7. **Use production-grade Vault** configuration (not dev mode)

## Next Steps

- Configure ingress controllers for external access
- Set up monitoring and logging (Azure Monitor, Prometheus, Grafana)
- Implement backup strategies for persistent volumes
- Configure auto-scaling for deployments
- Set up CI/CD pipelines for automated deployments
