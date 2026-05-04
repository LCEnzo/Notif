#!/usr/bin/env bash
set -euo pipefail

# ── Notif Production .env Writer ──────────────────────────────────
# Generates backend/.env and .env (project root) for production
# deployment on a VPS.
#
# Idempotent: refuses to overwrite unless --force is passed.
# ⚠️  --force regenerates DJANGO_SECRET_KEY — invalidates all sessions.
#
# Usage:
#   bash deploy/write-prod-env.sh                       # write both .env files
#   bash deploy/write-prod-env.sh --force               # overwrite, rotate secrets
#   NOTIF_DOMAIN=notif.example.com bash deploy/write-prod-env.sh
#
# Requires: openssl, git (in repo root)

cd "$(dirname "$0")/.."

DOMAIN="${NOTIF_DOMAIN:-notif.lcenzo.com}"
FORCE=false

if [[ "${1:-}" == "--force" ]]; then
	FORCE=true
fi

# ── Guard: refuse to overwrite without --force ────────────────────
for ENV_FILE in "backend/.env" ".env"; do
	if [[ -f "$ENV_FILE" ]] && [[ "$FORCE" != true ]]; then
		echo "ERROR: $ENV_FILE already exists."
		echo "  Use --force to overwrite, or edit it manually."
		echo "  bash deploy/write-prod-env.sh --force"
		exit 1
	fi
done

if [[ "$FORCE" == true ]]; then
	echo "⚠️  --force: regenerating DJANGO_SECRET_KEY (existing sessions will be invalidated)"
	echo ""
fi

# ── Generate secrets ──────────────────────────────────────────────
# openssl rand -hex produces only hex chars (0-9, a-f).
# These are safe inside Docker Compose env_file — no $ to mis-interpolate.
SECRET_KEY=$(openssl rand -hex 48)
GIT_HASH=$(git rev-parse --short HEAD)

# Admin URL: non-guessable suffix so bots can't find /admin/
ADMIN_SUFFIX=$(openssl rand -hex 16)
ADMIN_URL="${ADMIN_SUFFIX}/"
ADMIN_ROUTE="/${ADMIN_SUFFIX}/*"

# ── Write root .env (Compose interpolation — no secrets) ──────────
cat > ".env" << EOF
# Notif project-level environment (used by Docker Compose/Caddy)
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# No secrets here — secrets live in backend/.env
NOTIF_DOMAIN=$DOMAIN
DJANGO_ADMIN_ROUTE=$ADMIN_ROUTE
EOF

echo "✅  Wrote .env (root, Compose interpolation)"
echo "    NOTIF_DOMAIN=$DOMAIN"
echo "    DJANGO_ADMIN_ROUTE=$ADMIN_ROUTE"

# ── Write backend/.env (Django settings + secrets) ────────────────
cat > "backend/.env" << EOF
# Notif production environment (Django settings + secrets)
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

chmod 600 "backend/.env"

echo "✅  Wrote backend/.env"
echo "    DJANGO_SECRET_KEY:  ${SECRET_KEY:0:8}... (48 hex bytes)"
echo "    DJANGO_ADMIN_URL:   $ADMIN_URL"
echo "    GIT_HASH:           $GIT_HASH"
echo ""
echo "── Next commands ─────────────────────────────────────────────"
echo "  docker compose -f compose.yaml build"
echo "  docker compose -f compose.yaml --profile prod up -d"
echo "  curl https://$DOMAIN/api/v1/monitoring/status/"
echo ""
