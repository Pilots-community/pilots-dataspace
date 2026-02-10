#!/bin/bash
set -euo pipefail

# One-click setup for the Pilots Dataspace.
# Generates keys, builds Docker images, starts all services, and seeds identity data.
#
# Usage:
#   ./setup.sh          # normal setup (preserves existing volumes)
#   ./setup.sh --clean  # wipe volumes for a clean reset before starting

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CLEAN=false
for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN=true ;;
    -h|--help)
      echo "Usage: ./setup.sh [--clean]"
      echo ""
      echo "  --clean   Remove Docker volumes (database, vault) before starting"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Usage: ./setup.sh [--clean]"
      exit 1
      ;;
  esac
done

# ── Step 1: Check prerequisites ──────────────────────────────────────────────

echo "=== Checking prerequisites ==="

MISSING=()

if ! command -v java &>/dev/null; then
  MISSING+=("java (JDK 17+)")
fi

if ! command -v docker &>/dev/null; then
  MISSING+=("docker")
fi

if ! docker compose version &>/dev/null 2>&1; then
  MISSING+=("docker compose (v2 plugin)")
fi

if ! command -v jq &>/dev/null; then
  MISSING+=("jq")
fi

if ! command -v curl &>/dev/null; then
  MISSING+=("curl")
fi

if ! command -v python3 &>/dev/null; then
  MISSING+=("python3")
else
  if ! python3 -c "from cryptography.hazmat.primitives import serialization" 2>/dev/null \
    && ! /usr/bin/python3 -c "from cryptography.hazmat.primitives import serialization" 2>/dev/null; then
    MISSING+=("python3 'cryptography' library (pip install cryptography)")
  fi
fi

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "ERROR: Missing prerequisites:"
  for m in "${MISSING[@]}"; do
    echo "  - $m"
  done
  exit 1
fi

echo "  All prerequisites found."
echo ""

# ── Step 2: Generate keys ────────────────────────────────────────────────────

echo "=== Generating keys and credentials ==="
./generate-keys.sh
echo ""

# ── Step 3: Build Docker images ──────────────────────────────────────────────

echo "=== Building Docker images ==="
./gradlew dockerize
echo ""

# ── Step 4: Stop existing containers ─────────────────────────────────────────

if [ "$CLEAN" = true ]; then
  echo "=== Stopping containers and removing volumes (--clean) ==="
  docker compose down -v
else
  echo "=== Stopping existing containers ==="
  docker compose down
fi
echo ""

# ── Step 5: Start containers ─────────────────────────────────────────────────

echo "=== Starting containers ==="
docker compose up -d
echo ""

# ── Step 6: Wait for all services to be healthy ──────────────────────────────

echo "=== Waiting for all services to become healthy ==="

TIMEOUT=120
INTERVAL=5
ELAPSED=0

while true; do
  # Count services that are NOT yet healthy
  TOTAL=$(docker compose ps --format json | grep -c '"Service"' || true)
  HEALTHY=$(docker compose ps --format json | grep -c '"healthy"' || true)

  if [ "$TOTAL" -gt 0 ] && [ "$HEALTHY" -eq "$TOTAL" ]; then
    echo "  All $TOTAL services are healthy."
    break
  fi

  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "ERROR: Timed out after ${TIMEOUT}s waiting for services to become healthy."
    echo "Current status:"
    docker compose ps
    exit 1
  fi

  echo "  ${HEALTHY}/${TOTAL} healthy (${ELAPSED}s elapsed, timeout ${TIMEOUT}s)..."
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done
echo ""

# ── Step 7: Seed identity data ───────────────────────────────────────────────

echo "=== Seeding identity data ==="
./deployment/seed.sh
echo ""

# ── Done ─────────────────────────────────────────────────────────────────────

echo "========================================"
echo "  Dataspace is ready!"
echo "========================================"
echo ""
echo "Next steps — run the E2E example from the README:"
echo ""
echo "  # Set environment variables for Docker Compose mode:"
echo "  PROVIDER_DSP=\"http://provider-controlplane:19194/protocol\""
echo "  PROVIDER_DID=\"did:web:provider-identityhub%3A7093\""
echo ""
echo "  # Then follow the E2E steps (create asset, negotiate, transfer)."
echo "  # See: README.md -> 'End-to-End Example' section"
echo ""
