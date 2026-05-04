#!/usr/bin/env bash
set -euo pipefail

# ── Notif Production .env Writer ──────────────────────────────────
# Generates backend/.env for production deployment on a VPS.
# Safe to re-run: refuses to overwrite unless --force is passed.
#
# Usage:
#   bash deploy/write-prod-env.sh                       # interactive
#   bash deploy/write-prod-env.sh --force               # overwrite existing .env
#   NOTIF_DOMAIN=notif.example.com bash deploy/write-prod-env.sh
#
# Requires: openssl, git (in repo root)

cd "$(dirname "$0")/.."

ENV_FILE="backend/.env"
DOMAIN="${NOTIF_DOMAIN:-notif.lcenzo.com}"

# ── Guard: refuse to overwrite without --force ────────────────────
if [[ -f "$ENV_FILE" ]]; then
	if [[ "${1:-}" == "--force" ]]; then
		echo "Overwriting existing $ENV_FILE (--force)"
	else
		echo "ERROR: $ENV_FILE already exists."
		echo "  Use --force to overwrite, or edit it manually."
		echo "  bash deploy/write-prod-env.sh --force"
		exit 1
	fi
fi

# ── Generate secrets ──────────────────────────────────────────────
# openssl rand -hex produces only hex chars (0-9, a-f).
# These are safe inside Docker Compose env_file — no $ to mis-interpolate.
SECRET_KEY=$(openssl rand -hex 48)
GIT_HASH=$(git rev-parse --short HEAD)

# Admin URL: non-guessable suffix so bots can't find /admin/
ADMIN_SUFFIX=$(openssl rand -hex 16)
ADMIN_URL="${ADMIN_SUFFIX}/"

# ── Write backend/.env ────────────────────────────────────────────
cat > "$ENV_FILE" << EOF
# Notif production environment
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Domain:    $DOMAIN
# ⚠️  This file contains secrets.  Do not commit.

# ── environment ────────────────────────────────────────
NOTIF_ENV=production

# ── core ──────────────────────────────────────────────
DEBUG=false
DJANGO_SECRET_KEY=$SECRET_KEY
ALLOWED_HOSTS=$DOMAIN
CORS_ALLOWED_ORIGINS=https://$DOMAIN
CSRF_TRUSTED_ORIGINS=https://$DOMAIN
DJANGO_ADMIN_URL=$ADMIN_URL
SQLITE_PATH=/app/data/db.sqlite3

# ── static files ───────────────────────────────────────
STATIC_ROOT=staticfiles

# ── latency middleware ────────────────────────────────
DEV_API_LATENCY_MS=0
DEV_API_LATENCY_JITTER_MS=0

# ── build info ────────────────────────────────────────
VERSION=0.2.0
GIT_HASH=$GIT_HASH
EOF

chmod 600 "$ENV_FILE"

echo ""
echo "✅  Wrote $ENV_FILE for $DOMAIN"
echo "    DJANGO_SECRET_KEY:  ${SECRET_KEY:0:8}... (48 hex bytes)"
echo "    DJANGO_ADMIN_URL:   $ADMIN_URL"
echo "    GIT_HASH:           $GIT_HASH"
echo ""
echo "── Next commands ─────────────────────────────────────────────"
echo "  docker compose -f compose.yaml build"
echo "  docker compose -f compose.yaml --profile prod up -d"
echo "  curl https://$DOMAIN/api/v1/monitoring/status/"
echo ""
