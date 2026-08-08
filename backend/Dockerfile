# ── Production Dockerfile ──────────────────────────────────────────
# For local dev, use compose.override.yaml instead of changing this file.
#
# Build:  docker compose -f compose.yaml build
# Run:    docker compose -f compose.yaml --profile prod up -d
# Dev:    docker compose up -d          (auto-merges compose.override.yaml)

FROM python:3.14-slim

ARG GIT_HASH=dev

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    UV_LINK_MODE=copy \
    GIT_HASH=$GIT_HASH

WORKDIR /app

# ── system deps (lxml needs libxml2/libxslt) ──────────────────────
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential libxml2-dev libxslt1-dev sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# ── uv + deps (layer cached unless pyproject/uv.lock change) ──────
RUN pip install --no-cache-dir "uv>=0.11,<1.0"

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

# ── app code ──────────────────────────────────────────────────────
COPY . .

# ── static files (collect during build, served by Caddy) ───────────
# collectstatic imports Django settings. The real production secret is injected
# at runtime from backend/.env; this build-only value prevents config validation
# from failing while building an immutable image layer.
RUN mkdir -p /app/staticfiles \
    && DJANGO_SECRET_KEY=build-only-not-a-runtime-secret \
       DEBUG=false \
       NOTIF_ENV=production \
       ALLOWED_HOSTS=localhost \
       .venv/bin/python manage.py collectstatic --noinput --clear

# ── volume permissions (directory must exist before chown) ─────────
RUN mkdir -p /app/data /app/staticfiles \
    && useradd --create-home appuser \
    && chown -R appuser:appuser /app

ENV PATH="/app/.venv/bin:${PATH}"

USER appuser

EXPOSE 8000

# ── healthcheck ───────────────────────────────────────────────────
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; req = urllib.request.Request('http://localhost:8000/api/v1/monitoring/health/', headers={'X-Forwarded-Proto': 'https'}); urllib.request.urlopen(req, timeout=5)" || exit 1

ENTRYPOINT ["./docker-entrypoint.sh"]

# ── gunicorn defaults (override via compose command: for dev) ──────
# Workers: 2-4× CPU cores. For a small VPS with 2 vCPUs, 4 is fine.
# worker-tmp-dir /dev/shm: prevents heartbeat timeouts on low-memory hosts.
CMD ["gunicorn", "notif.wsgi:application", \
     "--bind", "0.0.0.0:8000", \
     "--workers", "4", \
     "--worker-tmp-dir", "/dev/shm", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "--max-requests", "1000", \
     "--max-requests-jitter", "200"]
