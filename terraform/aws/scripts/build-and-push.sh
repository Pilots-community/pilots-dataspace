#!/usr/bin/env bash
set -euo pipefail

# Builds the 4 connector images locally for linux/amd64 (matches the default
# Fargate runtime platform) and pushes them to ECR.
#
# Images built:
#   - identityhub, controlplane, dataplane: via `./gradlew dockerize`
#       (gradle task is defined in runtimes/<name>/build.gradle.kts and runs
#        ShadowJar + DockerBuildImage)
#   - dashboard: directly via `docker build dashboard/`
#
# Prerequisites:
#   - aws-vault session active (`aws-vault exec pilots --no-session`)
#   - Docker daemon running
#   - ECR repos created (./scripts/ecr-bootstrap.sh)
#   - JDK + Gradle wrapper in repo root (./gradlew)
#
# Usage:
#   ./scripts/build-and-push.sh [tag]
#
# tag defaults to the short git SHA (or "latest" if not in a git checkout).
# After pushing, set `image_tag = "<tag>"` in environments/<env>.tfvars and
# `terraform apply` to roll the new images out.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${TF_DIR}/../.." && pwd)"
REGION="${AWS_REGION:-eu-west-3}"
PLATFORM="${BUILD_PLATFORM:-linux/amd64}"

TAG="${1:-}"
if [[ -z "${TAG}" ]]; then
  TAG=$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo "latest")
fi

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

echo "Registry: ${REGISTRY}"
echo "Tag:      ${TAG}"
echo "Platform: ${PLATFORM}"
echo

# 1. Authenticate Docker to ECR (token good for 12h).
echo "=== ECR login ==="
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"

# 2. Build the 3 EDC services via the existing gradle dockerize task.
echo
echo "=== Building EDC images (gradle dockerize) ==="
cd "${REPO_ROOT}"
./gradlew dockerize "-Dplatform=${PLATFORM}"

# 3. Build the dashboard.
echo
echo "=== Building dashboard image ==="
docker build --platform="${PLATFORM}" -t "dashboard:latest" "${REPO_ROOT}/dashboard"

# 4. Tag + push everything.
echo
echo "=== Tag + push ==="
for svc in identityhub controlplane dataplane dashboard; do
  remote="${REGISTRY}/pilots/${svc}:${TAG}"
  docker tag "${svc}:latest" "${remote}"
  docker push "${remote}"
  echo "  pushed ${remote}"
done

echo
echo "Done. To roll out:"
echo "  1. set image_tag = \"${TAG}\" in environments/<env>.tfvars"
echo "  2. terraform apply -var-file=environments/<env>.tfvars"
echo "     (forces new task definitions; ECS rolls services)"
