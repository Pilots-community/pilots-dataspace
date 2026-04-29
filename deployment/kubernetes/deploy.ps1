# Quick deployment script for AKS
# Run this after building and pushing images to ACR

$ErrorActionPreference = "Stop"

Write-Host "Deploying Pilots Dataspace to AKS..." -ForegroundColor Green

# Deploy in order
Write-Host "`nCreating namespace..." -ForegroundColor Yellow
kubectl apply -f 00-namespace.yaml

Write-Host "`nCreating ConfigMaps..." -ForegroundColor Yellow
kubectl apply -f 01-configmap-postgres.yaml

Write-Host "`nChecking required Secrets..." -ForegroundColor Yellow
kubectl get secret pilots-dataspace-secrets -n pilots-dataspace *> $null
if ($LASTEXITCODE -ne 0) {
	Write-Host "Missing secret: pilots-dataspace-secrets" -ForegroundColor Red
	Write-Host "Create it before deploying. Example template:" -ForegroundColor Yellow
	Write-Host "  deployment/kubernetes/02-secrets.example.yaml" -ForegroundColor Gray
	Write-Host "Apply your local version with:" -ForegroundColor Yellow
	Write-Host "  kubectl apply -f 02-secrets.yaml" -ForegroundColor Gray
	exit 1
}

Write-Host "`nDeploying infrastructure (PostgreSQL, Vault, DID Server)..." -ForegroundColor Yellow
kubectl apply -f 03-postgres.yaml
kubectl apply -f 04-vault.yaml
kubectl apply -f 05-did-server.yaml

Write-Host "`nWaiting for infrastructure to be ready..." -ForegroundColor Yellow
kubectl wait --for=condition=ready pod -l app=postgres -n pilots-dataspace --timeout=120s
kubectl wait --for=condition=ready pod -l app=vault -n pilots-dataspace --timeout=120s
kubectl wait --for=condition=ready pod -l app=did-server -n pilots-dataspace --timeout=120s

Write-Host "`nDeploying IdentityHub components..." -ForegroundColor Yellow
kubectl apply -f 06-identityhub.yaml

Write-Host "`nWaiting for IdentityHub to be ready..." -ForegroundColor Yellow
kubectl wait --for=condition=ready pod -l app=provider-identityhub -n pilots-dataspace --timeout=180s

Write-Host "`nDeploying Control Plane components..." -ForegroundColor Yellow
kubectl apply -f 07-controlplane.yaml

Write-Host "`nWaiting for Control Plane to be ready..." -ForegroundColor Yellow
kubectl wait --for=condition=ready pod -l app=provider-controlplane -n pilots-dataspace --timeout=180s

Write-Host "`nDeploying Data Plane components..." -ForegroundColor Yellow
kubectl apply -f 08-dataplane.yaml

Write-Host "`nWaiting for Data Plane to be ready..." -ForegroundColor Yellow
kubectl wait --for=condition=ready pod -l app=provider-dataplane -n pilots-dataspace --timeout=180s

Write-Host "`n======================================" -ForegroundColor Green
Write-Host "Deployment completed successfully!" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green

Write-Host "`nChecking pod status..." -ForegroundColor Yellow
kubectl get pods -n pilots-dataspace

Write-Host "`nTo access services locally, run:" -ForegroundColor Cyan
Write-Host "kubectl port-forward -n pilots-dataspace svc/provider-controlplane 19193:19193" -ForegroundColor White


