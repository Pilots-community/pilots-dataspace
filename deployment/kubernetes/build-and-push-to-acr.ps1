# Build and push Docker images to Azure Container Registry (PowerShell version)
# Usage: .\build-and-push-to-acr.ps1 [-AcrName "pilotsdataspaceregistry"]

param(
    [string]$AcrName = "pilotsdataspaceregistry"
)

$ErrorActionPreference = "Stop"

# Configuration
$AcrLoginServer = "$AcrName.azurecr.io"

Write-Host "======================================" -ForegroundColor Green
Write-Host "Building and Pushing to ACR" -ForegroundColor Green
Write-Host "ACR: $AcrLoginServer" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green

# Login to ACR
Write-Host "`nLogging in to ACR..." -ForegroundColor Yellow
az acr login --name $AcrName

# Navigate to repo root (script lives in deployment\kubernetes)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..\..")
Set-Location $repoRoot

# Build Gradle projects
Write-Host "`nBuilding Java applications with Gradle..." -ForegroundColor Yellow
.\gradlew.bat build

# Build and push IdentityHub
Write-Host "`nBuilding and pushing IdentityHub..." -ForegroundColor Yellow
docker build `
  --build-arg JAR=runtimes/identityhub/build/libs/identityhub.jar `
  -t "$AcrLoginServer/identityhub:latest" `
  -f runtimes/identityhub/src/main/docker/Dockerfile `
  .
docker push "$AcrLoginServer/identityhub:latest"

# Build and push Control Plane
Write-Host "`nBuilding and pushing Control Plane..." -ForegroundColor Yellow
docker build `
  --build-arg JAR=runtimes/controlplane/build/libs/controlplane.jar `
  -t "$AcrLoginServer/controlplane:latest" `
  -f runtimes/controlplane/src/main/docker/Dockerfile `
  .
docker push "$AcrLoginServer/controlplane:latest"

# Build and push Data Plane
Write-Host "`nBuilding and pushing Data Plane..." -ForegroundColor Yellow
docker build `
  --build-arg JAR=runtimes/dataplane/build/libs/dataplane.jar `
  -t "$AcrLoginServer/dataplane:latest" `
  -f runtimes/dataplane/src/main/docker/Dockerfile `
  .
docker push "$AcrLoginServer/dataplane:latest"

# Import base images to ACR (if not already imported)
Write-Host "`nImporting base images to ACR..." -ForegroundColor Yellow

# Import postgres
Write-Host "Importing postgres:16-alpine..."
try {
    az acr import `
      --name $AcrName `
      --source docker.io/library/postgres:16-alpine `
      --image postgres:16-alpine `
      --force
} catch {
    Write-Host "postgres image already exists or import failed" -ForegroundColor Yellow
}

# Import nginx
Write-Host "Importing nginx:alpine..."
try {
    az acr import `
      --name $AcrName `
      --source docker.io/library/nginx:alpine `
      --image nginx:alpine `
      --force
} catch {
    Write-Host "nginx image already exists or import failed" -ForegroundColor Yellow
}

# Import python
Write-Host "Importing python:3-alpine..."
try {
    az acr import `
      --name $AcrName `
      --source docker.io/library/python:3-alpine `
      --image python:3-alpine `
      --force
} catch {
    Write-Host "python image already exists or import failed" -ForegroundColor Yellow
}

# Import vault
Write-Host "Importing hashicorp/vault:1.15..."
try {
    az acr import `
      --name $AcrName `
      --source docker.io/hashicorp/vault:1.15 `
      --image vault:1.15 `
      --force
} catch {
    Write-Host "vault image already exists or import failed" -ForegroundColor Yellow
}

Write-Host "`n======================================" -ForegroundColor Green
Write-Host "Build and push completed successfully!" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host "`nImages pushed to ACR:"
Write-Host "  - $AcrLoginServer/identityhub:latest"
Write-Host "  - $AcrLoginServer/controlplane:latest"
Write-Host "  - $AcrLoginServer/dataplane:latest"
Write-Host "  - $AcrLoginServer/postgres:16-alpine"
Write-Host "  - $AcrLoginServer/nginx:alpine"
Write-Host "  - $AcrLoginServer/python:3-alpine"
Write-Host "  - $AcrLoginServer/vault:1.15"
