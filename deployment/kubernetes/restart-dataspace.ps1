# Restart all dataspace components
# This script restarts all controlplanes and identityhubs to reload configuration

$ErrorActionPreference = "Stop"
$namespace = "pilots-dataspace"

Write-Host "`nRestarting Dataspace Components`n" -ForegroundColor Cyan

# Restart Provider Components
Write-Host "Restarting provider-controlplane..." -ForegroundColor Yellow
kubectl rollout restart -n $namespace deployment/provider-controlplane
Write-Host "Restarting provider-identityhub..." -ForegroundColor Yellow
kubectl rollout restart -n $namespace deployment/provider-identityhub

# Restart Consumer Components
Write-Host "Restarting consumer-controlplane..." -ForegroundColor Yellow
kubectl rollout restart -n $namespace deployment/consumer-controlplane
Write-Host "Restarting consumer-identityhub..." -ForegroundColor Yellow
kubectl rollout restart -n $namespace deployment/consumer-identityhub

Write-Host "`nWaiting for pods to be ready...`n" -ForegroundColor Cyan

# Wait for all pods to be ready
Write-Host "Waiting for provider-controlplane..." -ForegroundColor Gray
kubectl wait --for=condition=ready pod -l app=provider-controlplane -n $namespace --timeout=60s

Write-Host "Waiting for provider-identityhub..." -ForegroundColor Gray
kubectl wait --for=condition=ready pod -l app=provider-identityhub -n $namespace --timeout=60s

Write-Host "Waiting for consumer-controlplane..." -ForegroundColor Gray
kubectl wait --for=condition=ready pod -l app=consumer-controlplane -n $namespace --timeout=60s

Write-Host "Waiting for consumer-identityhub..." -ForegroundColor Gray
kubectl wait --for=condition=ready pod -l app=consumer-identityhub -n $namespace --timeout=60s

Write-Host "`nAll components restarted successfully!`n" -ForegroundColor Green

Write-Host "Remember to set up port forwarding:" -ForegroundColor Yellow
Write-Host "  kubectl port-forward svc/provider-controlplane 19193:19193 19194:19194 -n $namespace" -ForegroundColor Gray
Write-Host "  kubectl port-forward svc/consumer-controlplane 29193:29193 29194:29194 -n $namespace" -ForegroundColor Gray
Write-Host "  kubectl port-forward svc/provider-identityhub 7092:7092 -n $namespace" -ForegroundColor Gray
Write-Host "  kubectl port-forward svc/consumer-identityhub 7082:7082 -n $namespace" -ForegroundColor Gray
Write-Host "  kubectl port-forward svc/vault 8200:8200 -n $namespace" -ForegroundColor Gray
