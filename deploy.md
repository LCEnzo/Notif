# Deployment Runbook

Production deployment of the Notif backend + Flutter web frontend on a Hetzner VPS.
Two options: **Docker Compose** (full-stack, recommended) or **bare systemd** (backend-only, lighter).

Pick one. The app runs identically either way.

---

## Prerequisites

Before SSHing into anything:

1. **Domain** — bought (Porkbun, Namecheap, etc.) and delegated to Cloudflare's nameservers
2. **Cloudflare** — site added to your account; DNS A-record `notif` → `<VPS-IP>` with orange cloud (proxy) **enabled**
3. **SSL/TLS mode** in Cloudflare: **Full (strict)** — Caddy provides a valid Let's Encrypt certificate
4. **Hetzner CX22** (or any VPS with ≥1 GB RAM, Ubuntu 22.04 or 24.04)

### Domain delegation (Porkbun → Cloudflare)

Order matters: add the site to Cloudflare *first*, then point Porkbun at the nameservers it gives you.

1. In Cloudflare, **Add a site** → enter your domain → choose Free plan. Cloudflare assigns two nameservers (e.g. `xxx.ns.cloudflare.com`, `yyy.ns.cloudflare.com`).
2. In Porkbun, open the domain → **Authoritative Nameservers** → replace the defaults with the two Cloudflare nameservers. Disable Porkbun's URL Forwarding if it's set on the apex — it silently overrides A-records.
3. Wait for delegation. `dig NS notif.lcenzo.com +short` should return Cloudflare's NSes. Up to a few hours; sometimes minutes.
4. Only then create the `notif` A-record in Cloudflare. If Caddy boots before delegation completes it will burn Let's Encrypt rate-limit attempts trying to validate.

### TLS issuance behind Cloudflare's proxy

The orange cloud terminates TLS, which means **TLS-ALPN-01 cannot reach Caddy**. Caddy will fall back to HTTP-01, which usually works because Cloudflare proxies `/.well-known/acme-challenge/*` through — but it's fragile (a "Always Use HTTPS" rule or strict WAF rule can break it). Pick one:

- **Easiest:** grey-cloud the `notif` A-record during the first deploy so HTTP-01 hits the origin directly, then re-enable the orange cloud once `journalctl -u caddy` (or the compose logs) shows a certificate was obtained.
- **Most robust:** issue a [Cloudflare Origin Certificate](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/), drop it on the VPS, and tell Caddy to use it via `tls /path/to/cert.pem /path/to/key.pem`. Skips Let's Encrypt entirely and renews every 15 years.
- **DNS-01 with Cloudflare API token:** requires the `caddy-dns/cloudflare` module, which is **not** in `apt install caddy`. Either build Caddy with `xcaddy` or use the official Caddy image variant that bundles it.

The `Caddyfile` is pre-configured with Cloudflare's IP ranges in `trusted_proxies`, so behind the orange cloud, Caddy logs the real client IP from the `CF-Connecting-IP` header instead of Cloudflare's proxy IPs. When CF publishes new ranges (rare, see https://www.cloudflare.com/ips/), update the list in `Caddyfile` and reload Caddy.

---

## Option A: Docker Compose

Use when you want: full-stack deployment (backend API + Flutter web frontend), CI-identical environments, dev parity via `compose.override.yaml`, Caddy + TLS in Compose.

### A1. Provision the VPS

```bash
ssh root@<VPS-IP>

# Docker
curl -fsSL https://get.docker.com | sh
apt update && apt install -y docker-compose-v2 git

# Create deploy user (don't run services as root)
useradd -m -s /bin/bash deploy
usermod -aG docker deploy

su - deploy
```

### A2. Clone and configure

```bash
git clone https://github.com/LCEnzo/Notif /home/deploy/notif
cd /home/deploy/notif

# Generate both .env files with matching secrets, domain, and admin route.
# This creates:
#   .env        → NOTIF_DOMAIN + DJANGO_ADMIN_ROUTE (Compose/Caddy interpolation)
#   backend/.env → Django settings + secrets (DJANGO_ADMIN_URL matches the route)
bash deploy/write-prod-env.sh

# ── REQUIRED: edit backend/.env ──
# DEBUG=false
# NOTIF_ENV=production
# DJANGO_SECRET_KEY=<run after install/build, or paste a generated secret>
# ALLOWED_HOSTS=notif.lcenzo.com
# CORS_ALLOWED_ORIGINS=https://notif.lcenzo.com
# CSRF_TRUSTED_ORIGINS=https://notif.lcenzo.com
# DJANGO_ADMIN_URL=ops-<random-suffix>/   # don't leave the default "admin/" in prod
# SQLITE_PATH=/app/data/db.sqlite3
# STATIC_ROOT=staticfiles

vim backend/.env
```

`DJANGO_SECRET_KEY` belongs in `backend/.env`, not in the project-level `.env`. Compose reads `backend/.env` into the backend container; the project-level `.env` is only for Compose interpolation such as `NOTIF_DOMAIN`.

### A3. Build and launch

```bash
# Build all images (backend + frontend). collectstatic runs during the backend
# build; flutter build web runs during the frontend build.
docker compose -f compose.yaml build

# Start backend + frontend build + Caddy. The prod profile enables Caddy.
# The frontend service runs once to copy built assets from the image's
# /image-dist into the frontend_dist volume at /web-dist (via entrypoint.sh),
# then exits. Caddy mounts the same volume and serves from /web-dist.
docker compose -f compose.yaml --profile prod up -d

# Check all services are healthy.
docker compose -f compose.yaml ps

# Verify the API works — /status checks DB + returns version/commit.
curl https://notif.lcenzo.com/api/v1/monitoring/status/
# → {"status":"ok","db":"ok","version":"0.2.0","commit":"abc1234","environment":"production"}

# Verify the frontend is served.
curl -sI https://notif.lcenzo.com/ | head -3
# → HTTP/2 200
# → content-type: text/html

# Check Caddy got a certificate.
docker compose -f compose.yaml --profile prod logs caddy | grep -i "certificate"
```

Caddy serves the Flutter web app at `/`, the API at `/api/*`, and Django static files at `/static/*`. The backend is not published directly to the host — Caddy proxies internally.

### A4. Cron for scraping

```bash
crontab -e
# Add:
*/15 * * * * cd /home/deploy/notif && docker compose -f compose.yaml exec -T backend python manage.py scrape
```

### A5. Maintenance

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

# Rebuild only the frontend after UI changes
docker compose -f compose.yaml build frontend
docker compose -f compose.yaml --profile prod up -d frontend caddy

# Backup the database (sqlite3 .backup produces a consistent snapshot).
# Backups land on the persistent backend_data volume under /app/data/backups/.
mkdir -p backups
docker compose -f compose.yaml exec -T backend ./scripts/backup-db.sh
```

---

## Option B: Bare Metal + systemd

Use when you want: minimal RAM footprint (no Docker daemon), fewer moving parts, native journald logging. Recommended for CX22's 2 GB if you are comfortable managing Python and systemd directly.

The project currently requires Python `>=3.14,<3.15`. Ubuntu 22.04/24.04 default apt repositories usually do not provide `python3.14`, so this path installs Python with `uv` instead of apt.

### B1. Provision the VPS

```bash
ssh root@<VPS-IP>

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

# .env
sudo -u notif cp .env.example .env
# ── REQUIRED: edit .env (use /var/lib/notif for data paths) ──
# DEBUG=false
# NOTIF_ENV=production
# DJANGO_SECRET_KEY=<generate fresh>
# ALLOWED_HOSTS=notif.lcenzo.com
# CORS_ALLOWED_ORIGINS=https://notif.lcenzo.com
# CSRF_TRUSTED_ORIGINS=https://notif.lcenzo.com
# DJANGO_ADMIN_URL=ops-<random-suffix>/   # don't leave the default "admin/" in prod
# SQLITE_PATH=/var/lib/notif/db.sqlite3
# STATIC_ROOT=staticfiles

vim .env
chown notif:notif .env
chmod 600 .env

# Generate real secret key
sudo -u notif -H .venv/bin/python manage.py regenerate_secret_key --update-env

# Migrate + collect static
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
NOTIF_DOMAIN=notif.lcenzo.com
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
curl https://notif.lcenzo.com/api/v1/monitoring/status/
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

### B7. Maintenance

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

# Backup the database (sqlite3 .backup for consistent snapshot)
SQLITE_PATH=/var/lib/notif/db.sqlite3 BACKUP_DIR=/var/backups/notif /opt/notif/backend/scripts/backup-db.sh
```

---

## Post-Deployment Verification (both options)

```bash
# ── These should all work from any machine ──

# Frontend (Flutter web app)
open https://notif.lcenzo.com/

# Liveness (process alive?)
curl https://notif.lcenzo.com/api/v1/monitoring/health/

# Status (DB connectivity + version info)
curl https://notif.lcenzo.com/api/v1/monitoring/status/

# API docs (public)
open https://notif.lcenzo.com/api/v1/docs/

# Register a user
curl -X POST https://notif.lcenzo.com/api/v1/accounts/ \
  -H "Content-Type: application/json" \
  -d '{"username":"test","email":"test@example.com","password": "correct horse battery staple"}'

# Get a token
curl -X POST https://notif.lcenzo.com/api/v1/token/ \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password": "correct horse battery staple"}'
```

---

## Architecture (how the pieces connect)

```
Browser ──HTTPS──▶ Cloudflare ──HTTPS──▶ Caddy:443
                                            │
                         /api/* ──HTTP──▶ gunicorn:8000 ── Django
                         /static/* ── disk (zero Python overhead)
                         /* ── Flutter web app (SPA, from disk)
```

| Layer | What it does | Config |
|-------|-------------|--------|
| Cloudflare | DNS, DDoS protection, global CDN | A-record + orange cloud |
| Caddy | TLS termination, routing, static files | `Caddyfile` + deployment env |
| Flutter web | Frontend SPA at `/` | Built and copied into `frontend_dist` volume at `/web-dist` via entrypoint |
| gunicorn | WSGI server, runs Django | systemd unit or Docker |
| Django | Application — API, auth, scraping | `settings.py` + `backend/.env` |
| SQLite | Database | Single file in a persistent volume/directory |

### Routing

| Path | Served by | Notes |
|------|-----------|-------|
| `/` | Caddy → frontend_dist | Flutter web app with SPA fallback |
| `/api/*` | Caddy → gunicorn → Django | REST API |
| `/static/*` | Caddy → staticfiles volume | Django admin static assets |
| `/{$DJANGO_ADMIN_ROUTE}` | Caddy → gunicorn → Django | Admin panel (path set by DJANGO_ADMIN_ROUTE in root .env, matches DJANGO_ADMIN_URL in backend/.env) |

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
