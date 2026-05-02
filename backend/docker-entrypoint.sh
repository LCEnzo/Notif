#!/bin/sh
set -eu

# ── always run migrations ─────────────────────────────────────────
python manage.py migrate --noinput

# ── collect static if not already done during build ───────────────
# (Dockerfile does it at build time; dev override may skip it)
if [ -z "${SKIP_COLLECTSTATIC:-}" ]; then
    python manage.py collectstatic --noinput --clear 2>/dev/null || true
fi

exec "$@"
