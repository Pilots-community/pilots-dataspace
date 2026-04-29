# Build and push Docker images to Azure Container Registry without Docker Desktop
# Uses ACR Tasks to build images in the cloud
# Usage: .\build-and-push-to-acr-no-docker.ps1 [-AcrName "pilotsdataspaceregistry"]

param(
    [string]$AcrName = "pilotsdataspaceregistry"
)

$ErrorActionPreference = "Stop"

# Configuration
$AcrLoginServer = "$AcrName.azurecr.io"

Write-Host "======================================" -ForegroundColor Green
Write-Host "Building and Pushing to ACR (No Docker)" -ForegroundColor Green
Write-Host "ACR: $AcrLoginServer" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green

# Navigate to repo root (script lives in deployment\kubernetes)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..\..")
Set-Location $repoRoot

# Login to ACR
Write-Host "`nLogging in to ACR..." -ForegroundColor Yellow
az acr login --name $AcrName

# Build Gradle projects locally
Write-Host "`nBuilding Java applications with Gradle..." -ForegroundColor Yellow
.\gradlew.bat build -x test

# Build and push IdentityHub using ACR Tasks
Write-Host "`nBuilding and pushing IdentityHub to ACR..." -ForegroundColor Yellow
az acr build `
  --registry $AcrName `
  --image identityhub:latest `
  --file runtimes/identityhub/src/main/docker/Dockerfile `
  --build-arg JAR=runtimes/identityhub/build/libs/identityhub.jar `
  .

# Build and push Control Plane using ACR Tasks
Write-Host "`nBuilding and pushing Control Plane to ACR..." -ForegroundColor Yellow
az acr build `
  --registry $AcrName `
  --image controlplane:latest `
  --file runtimes/controlplane/src/main/docker/Dockerfile `
  --build-arg JAR=runtimes/controlplane/build/libs/controlplane.jar `
  .

# Build and push Data Plane using ACR Tasks
Write-Host "`nBuilding and pushing Data Plane to ACR..." -ForegroundColor Yellow
az acr build `
  --registry $AcrName `
  --image dataplane:latest `
  --file runtimes/dataplane/src/main/docker/Dockerfile `
  --build-arg JAR=runtimes/dataplane/build/libs/dataplane.jar `
  .

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
