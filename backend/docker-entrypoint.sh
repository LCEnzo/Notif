#!/bin/sh
set -eu

# ── always run migrations ─────────────────────────────────────────
python manage.py migrate --noinput

# ── collect static at startup too ─────────────────────────────────
# Dockerfile collects during build; this keeps a mounted static volume populated.
if [ -z "${SKIP_COLLECTSTATIC:-}" ]; then
    python manage.py collectstatic --noinput --clear
fi

exec "$@"
