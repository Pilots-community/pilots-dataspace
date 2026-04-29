# Create AKS cluster for pilots-dataspace deployment
# Usage: .\create-aks.ps1

param(
    [string]$ResourceGroup = "pilots-dataspace-rg",
    [string]$ClusterName = "pilots-dataspace-aks",
    [string]$AcrName = "pilotsdataspaceregistry",
    [string]$Location = "westeurope",
    [int]$NodeCount = 2,
    [string]$NodeVmSize = "Standard_B2s_v2"
)

$ErrorActionPreference = "Stop"

Write-Host "Creating AKS cluster..." -ForegroundColor Green
Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor Cyan
Write-Host "  Cluster Name: $ClusterName" -ForegroundColor Cyan
Write-Host "  Location: $Location" -ForegroundColor Cyan
Write-Host "  Node Count: $NodeCount" -ForegroundColor Cyan
Write-Host "  Node VM Size: $NodeVmSize" -ForegroundColor Cyan

# Create resource group if it doesn't exist
Write-Host "`nEnsuring resource group exists..." -ForegroundColor Yellow
az group create --name $ResourceGroup --location $Location

# Create AKS cluster
Write-Host "`nCreating AKS cluster (this will take 5-10 minutes)..." -ForegroundColor Yellow
az aks create `
  --resource-group $ResourceGroup `
  --name $ClusterName `
  --node-count $NodeCount `
  --node-vm-size $NodeVmSize `
  --enable-managed-identity `
  --generate-ssh-keys `
  --attach-acr $AcrName

# Get credentials
Write-Host "`nGetting AKS credentials..." -ForegroundColor Yellow
az aks get-credentials --resource-group $ResourceGroup --name $ClusterName --overwrite-existing

# Verify connection
Write-Host "`nVerifying connection..." -ForegroundColor Yellow
kubectl get nodes

Write-Host "`n======================================" -ForegroundColor Green
Write-Host "AKS cluster created successfully!" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host "`nCluster Name: $ClusterName"
Write-Host "Resource Group: $ResourceGroup"
Write-Host "`nYou can now deploy pilots-dataspace with:"
Write-Host "  cd deployment\kubernetes"
Write-Host "  .\deploy.ps1"
