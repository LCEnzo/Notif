#!/bin/sh
set -eu

# ── always run migrations ─────────────────────────────────────────
# migrate touches one database per run; the health app lives in its own file.
python manage.py migrate --noinput
python manage.py migrate --database health --noinput

# ── collect static at startup too ─────────────────────────────────
# Dockerfile collects during build; this keeps a mounted static volume populated.
if [ -z "${SKIP_COLLECTSTATIC:-}" ]; then
    python manage.py collectstatic --noinput --clear
fi

exec "$@"
