#!/bin/bash
# Build and push Docker images to Azure Container Registry
# Usage: ./build-and-push-to-acr.sh [ACR_NAME]

set -e

# Configuration
ACR_NAME="${1:-pilotsdataspaceregistry}"
ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Building and Pushing to ACR${NC}"
echo -e "${GREEN}ACR: ${ACR_LOGIN_SERVER}${NC}"
echo -e "${GREEN}======================================${NC}"

# Login to ACR
echo -e "\n${YELLOW}Logging in to ACR...${NC}"
az acr login --name "${ACR_NAME}"

# Build Gradle projects
echo -e "\n${YELLOW}Building Java applications with Gradle...${NC}"
./gradlew build

# Build and push IdentityHub
echo -e "\n${YELLOW}Building and pushing IdentityHub...${NC}"
docker build \
  --build-arg JAR=runtimes/identityhub/build/libs/identityhub.jar \
  -t "${ACR_LOGIN_SERVER}/identityhub:latest" \
  -f runtimes/identityhub/src/main/docker/Dockerfile \
  .
docker push "${ACR_LOGIN_SERVER}/identityhub:latest"

# Build and push Control Plane
echo -e "\n${YELLOW}Building and pushing Control Plane...${NC}"
docker build \
  --build-arg JAR=runtimes/controlplane/build/libs/controlplane.jar \
  -t "${ACR_LOGIN_SERVER}/controlplane:latest" \
  -f runtimes/controlplane/src/main/docker/Dockerfile \
  .
docker push "${ACR_LOGIN_SERVER}/controlplane:latest"

# Build and push Data Plane
echo -e "\n${YELLOW}Building and pushing Data Plane...${NC}"
docker build \
  --build-arg JAR=runtimes/dataplane/build/libs/dataplane.jar \
  -t "${ACR_LOGIN_SERVER}/dataplane:latest" \
  -f runtimes/dataplane/src/main/docker/Dockerfile \
  .
docker push "${ACR_LOGIN_SERVER}/dataplane:latest"

# Import base images to ACR (if not already imported)
echo -e "\n${YELLOW}Importing base images to ACR...${NC}"

# Import postgres
echo "Importing postgres:16-alpine..."
az acr import \
  --name "${ACR_NAME}" \
  --source docker.io/library/postgres:16-alpine \
  --image postgres:16-alpine \
  --force || echo "postgres image already exists or import failed"

# Import nginx
echo "Importing nginx:alpine..."
az acr import \
  --name "${ACR_NAME}" \
  --source docker.io/library/nginx:alpine \
  --image nginx:alpine \
  --force || echo "nginx image already exists or import failed"

# Import python
echo "Importing python:3-alpine..."
az acr import \
  --name "${ACR_NAME}" \
  --source docker.io/library/python:3-alpine \
  --image python:3-alpine \
  --force || echo "python image already exists or import failed"

# Import vault
echo "Importing hashicorp/vault:1.15..."
az acr import \
  --name "${ACR_NAME}" \
  --source docker.io/hashicorp/vault:1.15 \
  --image vault:1.15 \
  --force || echo "vault image already exists or import failed"

echo -e "\n${GREEN}======================================${NC}"
echo -e "${GREEN}Build and push completed successfully!${NC}"
echo -e "${GREEN}======================================${NC}"
echo -e "\nImages pushed to ACR:"
echo -e "  - ${ACR_LOGIN_SERVER}/identityhub:latest"
echo -e "  - ${ACR_LOGIN_SERVER}/controlplane:latest"
echo -e "  - ${ACR_LOGIN_SERVER}/dataplane:latest"
echo -e "  - ${ACR_LOGIN_SERVER}/postgres:16-alpine"
echo -e "  - ${ACR_LOGIN_SERVER}/nginx:alpine"
echo -e "  - ${ACR_LOGIN_SERVER}/python:3-alpine"
echo -e "  - ${ACR_LOGIN_SERVER}/vault:1.15"
