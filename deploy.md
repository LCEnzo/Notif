# Deployment Runbook

Production deployment of the Notif backend on a Hetzner CX22 (or equivalent ~€4/mo VPS).
Two options: **Docker Compose** (portable, heavier) or **bare systemd** (lighter, fewer moving parts).

Pick one. The app runs identically either way.

> **Current phase:** backend-only.  Flutter frontend deployment is not included.
> **Platform:** Debian 13 (trixie), Docker Compose v2 via `docker compose` (the
> plugin, not the standalone `docker-compose` binary).

---

## Prerequisites

Before SSHing into anything:

1. **Domain** — bought and pointing at Cloudflare's nameservers
2. **Cloudflare** — DNS A-record `notif` → `<VPS-IP>` with **grey cloud** (DNS-only, not proxied) initially:
   - Grey-cloud lets Caddy get a Let's Encrypt certificate without Cloudflare's edge interfering
   - Once TLS is verified, switch to **orange cloud** (proxied)
3. **SSL/TLS mode** in Cloudflare: **Full (strict)** — Caddy provides a valid Let's Encrypt certificate
4. **Hetzner CX22** (or any VPS with ≥1 GB RAM)
5. **Do not enable DNSSEC** or restrict the origin firewall to Cloudflare IPs until after basic deploy is verified — both can break first-time TLS issuance

---

## First-Deploy Cloudflare Flow

This is the exact sequence used on the first production deploy. Follow it for any fresh VPS:

```
Step 1: Cloudflare A record notif → VPS IPv4, grey-cloud (DNS-only)
Step 2: Start Caddy + backend → Caddy obtains Let's Encrypt certificate
Step 3: Verify /health and /status respond correctly over HTTPS
Step 4: Only then switch Cloudflare record to orange-cloud (proxied)
Step 5: Keep SSL/TLS mode Full (strict)
```

If you skip step 1 and go straight to orange-cloud, Cloudflare's TLS terminates at the edge and Caddy sees the CF edge cert — it will not obtain its own Let's Encrypt cert, and you'll get certificate errors locally.

---

## Option A: Docker Compose

Use when you want: CI-identical environments, dev parity via `compose.override.yaml`, Caddy + TLS in Compose, or eventual multi-service orchestration.

### A1. Provision the VPS

```bash
ssh root@<VPS-IP>

# If apt update fails with "File has unexpected size. Mirror sync in progress?",
# the Hetzner Debian mirror is mid-sync.  Disable it and use deb.debian.org:
#   mv /etc/apt/sources.list.d/hetzner-mirror.list /etc/apt/sources.list.d/hetzner-mirror.list.bak
#   apt update
# Then re-enable after the sync window passes.

# Docker (docker-ce + docker-compose-v2 plugin)
curl -fsSL https://get.docker.com | sh
apt update && apt install -y docker-compose-v2 git

# Create deploy user (don't run services as root)
useradd -m -s /bin/bash deploy
usermod -aG docker deploy

su - deploy
```

> **Note:** Docker Compose is installed as the `docker-compose-plugin` package.
> All commands use `docker compose` (v2 plugin syntax), not `docker-compose` (v1 standalone).
> The two are different binaries — this runbook assumes v2.

### A2. Clone and write production .env

```bash
git clone https://github.com/LCEnzo/Notif /home/deploy/notif
cd /home/deploy/notif

# Write backend/.env with generated secrets, domain, and git hash.
# Safe to re-run with --force if you need to rotate secrets.
bash deploy/write-prod-env.sh
```

The script writes these values into `backend/.env`:

| Key | Value |
|-----|-------|
| `DEBUG` | `false` |
| `NOTIF_ENV` | `production` |
| `DJANGO_SECRET_KEY` | 48 hex bytes from `openssl rand -hex 48` |
| `ALLOWED_HOSTS` | your domain |
| `CORS_ALLOWED_ORIGINS` | `https://<your-domain>` |
| `CSRF_TRUSTED_ORIGINS` | `https://<your-domain>` |
| `DJANGO_ADMIN_URL` | random 16-hex suffix with trailing `/` |
| `SQLITE_PATH` | `/app/data/db.sqlite3` |
| `GIT_HASH` | `git rev-parse --short HEAD` |
| `DEV_API_LATENCY_MS` / `JITTER_MS` | `0` (no artificial latency in prod) |

To override the domain, set `NOTIF_DOMAIN` before running:

```bash
NOTIF_DOMAIN=notif.example.com bash deploy/write-prod-env.sh
```

If `backend/.env` already exists, the script refuses to overwrite unless you pass `--force`.

> **Why a script instead of manual editing?**  Manual editing on the first deploy
> led to `$` characters in `DJANGO_SECRET_KEY` that Docker Compose tried to
> interpolate from `env_file`, silently mutating the secret.  The script generates
> hex-only secrets and writes all domain-derived values correctly in one shot.

### A3. Build and launch

```bash
# Build the image. collectstatic runs during the build with a build-only dummy secret.
docker compose -f compose.yaml build

# Start backend + Caddy. The prod profile enables Caddy.
docker compose -f compose.yaml --profile prod up -d

# Check containers are running.
docker compose -f compose.yaml --profile prod ps
```

### A4. Verify

```bash
# Liveness — is the process alive?
curl -i https://notif.yourdomain.com/api/v1/monitoring/health/

# Status — can it serve traffic? Returns version + commit hash.
curl -i https://notif.yourdomain.com/api/v1/monitoring/status/
# → {"status":"ok","db":"ok","version":"0.2.0","commit":"abc1234","environment":"production"}

# Confirm Caddy got a certificate.
docker compose -f compose.yaml --profile prod logs caddy | grep -i "certificate"

# Full verification checklist:
#   docker compose -f compose.yaml --profile prod ps
#   curl -i https://notif.yourdomain.com/api/v1/monitoring/health/
#   curl -i https://notif.yourdomain.com/api/v1/monitoring/status/
#   docker compose -f compose.yaml --profile prod logs caddy | tail -20
#   docker compose -f compose.yaml --profile prod logs backend | tail -20
```

The backend is not published directly to the host in production Compose. Caddy exposes ports 80/443 and proxies internally to `backend:8000`.

### A5. Cron for scraping

```bash
crontab -e
# Add:
*/15 * * * * cd /home/deploy/notif && docker compose -f compose.yaml run --rm backend python manage.py scrape
```

### A6. Database backups

A backup script is included at `backend/scripts/backup-db.sh`. It uses `sqlite3 .backup`
for atomic snapshots and retains the 10 most recent backups.

```bash
# Run a backup (inside the running container):
docker compose -f compose.yaml exec -T backend ./scripts/backup-db.sh

# Backups land in a 'backups/' directory next to the SQLite file:
#   /app/data/backups/db-YYYYMMDD-HHMMSS.sqlite3
# By default, the 10 most recent are kept; older ones are rotated out.

# Copy backups to the host:
docker compose -f compose.yaml cp backend:/app/data/backups /home/deploy/notif/backups/

# ── Daily cron backup (add to host crontab) ──
# 3:00 AM every day — sqlite3 .backup for atomic copies.
0 3 * * * cd /home/deploy/notif && docker compose -f compose.yaml exec -T backend ./scripts/backup-db.sh
```

### A7. Maintenance

```bash
# View logs
docker compose -f compose.yaml --profile prod logs -f backend caddy

# Restart after config changes
docker compose -f compose.yaml --profile prod restart backend caddy

# Pull updates
cd /home/deploy/notif
git pull
docker compose -f compose.yaml build
docker compose -f compose.yaml --profile prod up -d
```

---

## Option B: Bare Metal + systemd

Use when you want: minimal RAM footprint (no Docker daemon), fewer moving parts, native journald logging. Recommended for CX22's 2 GB if you are comfortable managing Python and systemd directly.

The project currently requires Python `>=3.14,<3.15`. Ubuntu 22.04/24.04 default apt repositories usually do not provide `python3.14`, so this path installs Python with `uv` instead of apt.

### B1. Provision the VPS

```bash
ssh root@<VPS-IP>

# If apt update fails with "File has unexpected size. Mirror sync in progress?",
# see the note in A1 above — disable the Hetzner mirror temporarily.

# Runtime deps + Caddy. uv manages Python 3.14.
apt update && apt install -y curl git caddy
curl -LsSf https://astral.sh/uv/install.sh | sh
install -m 755 /root/.local/bin/uv /usr/local/bin/uv

# Create app user (runs the service, can't log in)
useradd -r -s /usr/sbin/nologin -d /opt/notif notif

# Create source + data directories
mkdir -p /opt/notif /var/lib/notif /var/backups/notif
chown -R notif:notif /opt/notif /var/lib/notif /var/backups/notif
```

### B2. Clone, venv, install

```bash
git clone https://github.com/LCEnzo/Notif /opt/notif
chown -R notif:notif /opt/notif
cd /opt/notif/backend

# Production Python + venv from pyproject.toml/uv.lock
sudo -u notif -H uv python install 3.14
sudo -u notif -H uv sync --frozen --no-dev --python 3.14

# Write production .env (generates secrets, sets domain-derived values)
cd /opt/notif
NOTIF_DOMAIN=notif.yourdomain.com bash deploy/write-prod-env.sh
chown notif:notif backend/.env

# Override SQLITE_PATH for bare-metal (the script writes /app/data/ by default)
# Edit backend/.env and change:
#   SQLITE_PATH=/var/lib/notif/db.sqlite3

# Migrate + collect static
cd backend
sudo -u notif -H .venv/bin/python manage.py migrate --noinput
sudo -u notif -H .venv/bin/python manage.py collectstatic --noinput
```

### B3. systemd service

```bash
cat > /etc/systemd/system/notif.service << 'UNIT'
[Unit]
Description=Notif API (gunicorn)
After=network.target

[Service]
User=notif
Group=notif
WorkingDirectory=/opt/notif/backend
EnvironmentFile=/opt/notif/backend/.env
ExecStart=/opt/notif/backend/.venv/bin/gunicorn notif.wsgi:application \
    --bind 127.0.0.1:8000 \
    --workers 2 \
    --worker-tmp-dir /dev/shm \
    --access-logfile - \
    --error-logfile -
Restart=always
RestartSec=5

# Security hardening — good enough for a single-app VPS
PrivateTmp=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/opt/notif/backend/staticfiles /var/lib/notif /var/backups/notif

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now notif
```

### B4. Caddy

```bash
# Configure Caddy env for this deployment.
cat > /etc/caddy/notif.env << 'ENV'
NOTIF_DOMAIN=notif.yourdomain.com
STATIC_ROOT=/opt/notif/backend/staticfiles
BACKEND_UPSTREAM=localhost
BACKEND_PORT=8000
ENV

# Load the env file before Caddy starts.
systemctl edit caddy
```

Add this override, then save:

```ini
[Service]
EnvironmentFile=/etc/caddy/notif.env
```

Then install and reload the Caddyfile:

```bash
ln -sf /opt/notif/Caddyfile /etc/caddy/Caddyfile
systemctl daemon-reload
systemctl enable --now caddy
systemctl reload caddy
```

### B5. Verify

```bash
# Check both services are running
systemctl status notif caddy

# Status check (local, through gunicorn). Header avoids HTTPS redirect from Django.
curl -H 'X-Forwarded-Proto: https' http://localhost:8000/api/v1/monitoring/status/
# → {"status":"ok","db":"ok","version":"0.2.0","commit":"abc1234","environment":"production"}

# Status check (public, through Caddy)
curl https://notif.yourdomain.com/api/v1/monitoring/status/
# → {"status":"ok","db":"ok","version":"0.2.0","commit":"abc1234","environment":"production"}

# Check Caddy got a certificate
journalctl -u caddy --no-pager | grep -i "certificate"
```

### B6. Cron for scraping

```bash
cat > /etc/cron.d/notif-scrape << 'CRON'
# Scrape every 15 minutes
*/15 * * * * notif cd /opt/notif/backend && /opt/notif/backend/.venv/bin/python manage.py scrape
CRON
```

### B7. Database backups

The backup script at `backend/scripts/backup-db.sh` works outside Docker too. It
respects `SQLITE_PATH` and `BACKUP_DIR` from the environment.

```bash
# Run a backup
sudo -u notif -H SQLITE_PATH=/var/lib/notif/db.sqlite3 \
    BACKUP_DIR=/var/backups/notif \
    bash /opt/notif/backend/scripts/backup-db.sh

# ── Daily cron backup ──
# Add to /etc/cron.d/notif-backup:
# 0 3 * * * notif SQLITE_PATH=/var/lib/notif/db.sqlite3 BACKUP_DIR=/var/backups/notif bash /opt/notif/backend/scripts/backup-db.sh
```

### B8. Maintenance

```bash
# View service logs
journalctl -u notif -f
journalctl -u caddy -f

# Restart after .env or code changes
systemctl restart notif
systemctl reload caddy

# Pull updates
cd /opt/notif
sudo -u notif git pull
cd /opt/notif/backend
sudo -u notif -H uv sync --frozen --no-dev --python 3.14
sudo -u notif -H .venv/bin/python manage.py migrate --noinput
sudo -u notif -H .venv/bin/python manage.py collectstatic --noinput
systemctl restart notif
systemctl reload caddy
```

---

## Post-Deployment Verification (both options)

```bash
# ── These should all work from any machine ──

# Liveness (process alive?)
curl https://notif.yourdomain.com/api/v1/monitoring/health/

# Status (DB connectivity + version info)
curl https://notif.yourdomain.com/api/v1/monitoring/status/

# API docs (public)
open https://notif.yourdomain.com/api/v1/docs/

# Register a user
curl -X POST https://notif.yourdomain.com/api/v1/accounts/ \
  -H "Content-Type: application/json" \
  -d '{"username":"test","email":"test@example.com","password":"correcthorsebatterystaple"}'

# Get a token
curl -X POST https://notif.yourdomain.com/api/v1/token/ \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password":"correcthorsebatterystaple"}'
```

---

## Architecture (how the pieces connect)

```
Browser ──HTTPS──▶ Cloudflare ──HTTPS──▶ Caddy:443 ──HTTP──▶ gunicorn:8000 ── Django
                                            │
                                            └── /static/* from disk (zero Python)
```

| Layer | What it does | Config |
|-------|-------------|--------|
| Cloudflare | DNS, DDoS protection, global CDN | A-record + orange cloud |
| Caddy | TLS termination, static files, reverse proxy | `Caddyfile` + deployment env |
| gunicorn | WSGI server, runs Django | systemd unit or Docker |
| Django | Application — API, auth, scraping | `settings.py` + `backend/.env` |
| SQLite | Database | Single file in a persistent volume/directory |

---

## Firewall

Hetzner VPS comes with no firewall by default. Add one:

```bash
# Allow SSH, HTTP, HTTPS. Drop everything else.
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable
```

In production Compose, only Caddy publishes public ports. In bare-metal mode, gunicorn binds to `127.0.0.1:8000`, so it is not reachable from outside. Only Caddy (80/443) and SSH (22) should be exposed.

---

## Monitoring (free, optional)

| Service | What it monitors | Setup |
|---------|-----------------|-------|
| [UptimeRobot](https://uptimerobot.com) | `GET /api/v1/monitoring/status/` every 5 min | 2 min, free tier |
| [Healthchecks.io](https://healthchecks.io) | Cron scrape jobs — alerts if a run is missed | 2 min, free tier |
