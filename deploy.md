# Deployment Runbook

Production deployment of the Notif backend on a Hetzner CX22 (or equivalent ~€4/mo VPS).
Two options: **Docker Compose** (portable, heavier) or **bare systemd** (lighter, fewer moving parts).

Pick one. The app runs identically either way.

---

## Prerequisites

Before SSHing into anything:

1. **Domain** — bought and pointing at Cloudflare's nameservers
2. **Cloudflare** — DNS A-record `notif` → `<VPS-IP>` with orange cloud (proxy) **enabled**
3. **SSL/TLS mode** in Cloudflare: **Full (strict)** — Caddy provides a valid Let's Encrypt certificate
4. **Hetzner CX22** (or any VPS with ≥1 GB RAM, Ubuntu 22.04 or 24.04)

---

## Option A: Docker Compose

Use when you want: CI-identical environments, dev parity via `compose.override.yaml`, or eventual multi-service orchestration.

### A1. Provision the VPS (~5 min)

```bash
ssh root@<VPS-IP>

# Docker
curl -fsSL https://get.docker.com | sh
apt install -y docker-compose-v2 git

# Create deploy user (don't run services as root)
useradd -m -s /bin/bash deploy
usermod -aG docker deploy

su - deploy
```

### A2. Clone and configure (~5 min)

```bash
git clone https://github.com/LCEnzo/Notif /home/deploy/notif
cd /home/deploy/notif

# Create production .env from the example
cp backend/.env.example backend/.env

# ── REQUIRED: edit backend/.env ──
# DEBUG=false
# NOTIF_ENV=production
# DJANGO_SECRET_KEY=<run: python manage.py regenerate_secret_key>
# ALLOWED_HOSTS=notif.yourdomain.com
# CORS_ALLOWED_ORIGINS=https://notif.yourdomain.com
# SQLITE_PATH=/app/data/db.sqlite3

vim backend/.env
```

### A3. Build and launch (~3 min)

```bash
# Edit Caddyfile — replace notif.example.com with your domain
sed -i 's/notif.example.com/notif.yourdomain.com/' Caddyfile

# Build the image
docker compose -f compose.yaml build

# Start everything
docker compose -f compose.yaml up -d

# Check it's alive
curl http://localhost:8000/api/v1/monitoring/health/
# → {"status":"ok","db":"ok"}

# Check Caddy got a certificate
docker compose logs caddy | grep "certificate"
```

### A4. Cron for scraping

```bash
crontab -e
# Add:
*/15 * * * * cd /home/deploy/notif && docker compose -f compose.yaml run --rm backend python manage.py scrape
```

### A5. Maintenance

```bash
# View logs
docker compose -f compose.yaml logs -f backend

# Restart after config changes
docker compose -f compose.yaml restart backend

# Pull updates
cd /home/deploy/notif
git pull
docker compose -f compose.yaml build
docker compose -f compose.yaml up -d

# Backup the database
docker compose -f compose.yaml exec backend cp /app/data/db.sqlite3 /app/data/db-$(date +%Y%m%d).sqlite3
docker compose -f compose.yaml cp backend:/app/data/db-$(date +%Y%m%d).sqlite3 ./backups/
```

---

## Option B: Bare Metal + systemd

Use when you want: minimal RAM footprint (no Docker daemon), fewer moving parts, native journald logging. Recommended for CX22's 2 GB.

### B1. Provision the VPS (~3 min)

```bash
ssh root@<VPS-IP>

# Install runtime deps
apt update && apt install -y python3.14 python3.14-venv git caddy

# Create app user (runs the service, can't log in)
useradd -r -s /bin/false -d /opt/notif notif

# Create source + data directories
mkdir -p /opt/notif /var/lib/notif /var/backups/notif
chown -R notif:notif /opt/notif /var/lib/notif /var/backups/notif
```

### B2. Clone, venv, install (~3 min)

```bash
git clone https://github.com/LCEnzo/Notif /opt/notif
cd /opt/notif/backend

# Production venv
python3.14 -m venv .venv
.venv/bin/pip install uv
uv sync --no-dev

# .env
cp .env.example .env
# ── REQUIRED: edit .env (use /var/lib/notif for data paths) ──
# DEBUG=false
# NOTIF_ENV=production
# DJANGO_SECRET_KEY=<generate fresh>
# ALLOWED_HOSTS=notif.yourdomain.com
# CORS_ALLOWED_ORIGINS=https://notif.yourdomain.com
# SQLITE_PATH=/var/lib/notif/db.sqlite3

vim .env

# Generate real secret key
.venv/bin/python manage.py regenerate_secret_key --update-env

# Migrate + collect static
.venv/bin/python manage.py migrate --noinput
.venv/bin/python manage.py collectstatic --noinput
```

### B3. systemd service (~2 min)

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
ReadWritePaths=/var/lib/notif /var/backups/notif

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now notif
```

### B4. Caddy (~1 min)

```bash
# Edit the Caddyfile — replace notif.example.com with your domain
sed -i 's/notif.example.com/notif.yourdomain.com/' /opt/notif/Caddyfile

# Link into Caddy's config directory
ln -sf /opt/notif/Caddyfile /etc/caddy/Caddyfile

systemctl enable --now caddy
```

### B5. Verify

```bash
# Check both services are running
systemctl status notif caddy

# Health check (local)
curl http://localhost:8000/api/v1/monitoring/health/
# → {"status":"ok","db":"ok"}

# Health check (public, through Caddy)
curl https://notif.yourdomain.com/api/v1/monitoring/health/
# → {"status":"ok","db":"ok"}

# Check Caddy got a certificate
journalctl -u caddy --no-pager | grep -i "certificate"
```

### B6. Cron for scraping

```bash
cat > /etc/cron.d/notif-scrape << 'CRON'
# Scrape every 15 minutes
*/15 * * * * notif /opt/notif/backend/.venv/bin/python /opt/notif/backend/manage.py scrape
CRON
```

### B7. Maintenance

```bash
# View service logs
journalctl -u notif -f
journalctl -u caddy -f

# Restart after .env or code changes
systemctl restart notif

# Pull updates
cd /opt/notif
sudo -u notif git pull
sudo -u notif /opt/notif/backend/.venv/bin/pip install uv
cd /opt/notif/backend
sudo -u notif uv sync --no-dev
systemctl restart notif

# Backup the database
cp /var/lib/notif/db.sqlite3 /var/backups/notif/db-$(date +%Y%m%d-%H%M).sqlite3
```

---

## Post-Deployment Verification (both options)

```bash
# ── These should all work from any machine ──

# Health
curl https://notif.yourdomain.com/api/v1/monitoring/health/

# API docs (public)
open https://notif.yourdomain.com/api/v1/docs/

# Register a user
curl -X POST https://notif.yourdomain.com/api/v1/accounts/ \
  -H "Content-Type: application/json" \
  -d '{"username":"test","email":"test@example.com","password":"correct horse battery staple"}'

# Get a token
curl -X POST https://notif.yourdomain.com/api/v1/token/ \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password":"correct horse battery staple"}'
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
| Caddy | TLS termination, static files, reverse proxy | `Caddyfile` (12 lines) |
| gunicorn | WSGI server, runs Django | systemd unit or Docker |
| Django | Application — API, auth, scraping | `settings.py` + `.env` |
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

gunicorn binds to `127.0.0.1:8000` — not reachable from outside. Only Caddy (on 443) and SSH (on 22) are exposed.

---

## Monitoring (free, optional)

| Service | What it monitors | Setup |
|---------|-----------------|-------|
| [UptimeRobot](https://uptimerobot.com) | `GET /api/v1/monitoring/health/` every 5 min | 2 min, free tier |
| [Healthchecks.io](https://healthchecks.io) | Cron scrape jobs — alerts if a run is missed | 2 min, free tier |
