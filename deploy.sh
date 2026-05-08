#!/bin/sh
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

echo "=== Pulling latest code ==="
git pull

GIT_HASH=$(git rev-parse --short HEAD)
APP_VERSION=$(awk -F': *' '$1 == "version" { print $2; exit }' frontend/pubspec.yaml)
APP_VERSION=${APP_VERSION%%+*}
if [ -z "$APP_VERSION" ]; then
    echo "ERROR: Could not read app version from frontend/pubspec.yaml" >&2
    exit 1
fi
echo "=== Deploying commit: $GIT_HASH (version $APP_VERSION) ==="

set_env_value() {
    key=$1
    value=$2
    file=$3
    if grep -q "^$key=" "$file"; then
        sed -i "s/^$key=.*/$key=$value/" "$file"
    else
        printf "\n%s=%s\n" "$key" "$value" >> "$file"
    fi
}

# Inject into backend/.env so Compose picks it up at runtime.
set_env_value VERSION "$APP_VERSION" backend/.env
set_env_value GIT_HASH "$GIT_HASH" backend/.env

# Build with build arg so the image ENV has the hash as fallback.
docker compose -f compose.yaml build --build-arg GIT_HASH="$GIT_HASH"

# Start backend + Caddy (prod profile enables Caddy).
docker compose -f compose.yaml --profile prod up -d

echo ""
echo "=== Deploy complete ==="
echo "Verify: curl https://notif.lcenzo.com/api/v1/monitoring/status/"
