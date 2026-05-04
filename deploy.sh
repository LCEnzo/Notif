#!/bin/sh
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

echo "=== Pulling latest code ==="
git pull

GIT_HASH=$(git rev-parse --short HEAD)
echo "=== Deploying commit: $GIT_HASH ==="

# Inject into backend/.env so Compose picks it up at runtime.
sed -i "s/^GIT_HASH=.*/GIT_HASH=$GIT_HASH/" backend/.env

# Build with build arg so the image ENV has the hash as fallback.
docker compose -f compose.yaml build --build-arg GIT_HASH="$GIT_HASH"

# Start backend + Caddy (prod profile enables Caddy).
docker compose -f compose.yaml --profile prod up -d

echo ""
echo "=== Deploy complete ==="
echo "Verify: curl https://notif.lcenzo.com/api/v1/monitoring/status/"
