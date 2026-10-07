# VPS Host Operations

This document is the host-level contract for the `notif` VPS. Application
configuration stays in the repo and `.env` files; boot behavior, unattended OS
maintenance, and scheduled jobs are owned by systemd.

Current production host facts, verified on 2026-05-18:

- OS: Debian GNU/Linux 13 (`trixie`) on Hetzner.
- Checkout: `/home/luka/notif`.
- Runtime stack: Docker Compose with `backend` and Compose-managed `caddy`.
- Existing containers: `notif-backend-1`, `notif-caddy-1`.
- `docker.service` and `unattended-upgrades.service` are enabled.

## Host Layout

`./deploy.sh` writes one documented env file for the Compose stack:

```bash
sudo install -d -m 0755 /etc/notif
sudo tee /etc/notif/notif-compose.env >/dev/null <<'ENV'
NOTIF_DEPLOY_DIR=/home/luka/notif
NOTIF_COMPOSE_FILE=compose.yaml
NOTIF_COMPOSE_PROFILE=prod
ENV
sudo chmod 0644 /etc/notif/notif-compose.env
```

If the checkout moves, update only `NOTIF_DEPLOY_DIR`.

## Boot Services

`./deploy.sh` installs and enables the repo-managed units on every deploy, then
activates the built stack through systemd with
`systemctl reload-or-restart notif-compose.service`. The script does not invoke
`docker compose up` directly. For manual repair, run:

```bash
cd /home/luka/notif
sudo install -m 0644 deploy/systemd/notif-compose.service /etc/systemd/system/notif-compose.service
sudo install -m 0644 deploy/systemd/notif-run-due-tasks.service /etc/systemd/system/notif-run-due-tasks.service
sudo install -m 0644 deploy/systemd/notif-run-due-tasks.timer /etc/systemd/system/notif-run-due-tasks.timer
sudo systemctl daemon-reload
sudo systemctl enable --now docker.service
sudo systemctl enable notif-compose.service notif-run-due-tasks.timer
sudo systemctl reload-or-restart notif-compose.service
sudo systemctl start notif-run-due-tasks.timer
```

`notif-compose.service` starts the Compose stack on boot and reloads by running
`docker compose up -d --remove-orphans`. The backend and Caddy containers also
use Docker restart policies, but systemd is the explicit boot and deployment
lifecycle owner.

The timer replaces host crontab entries for routine app work:

```bash
systemctl list-timers 'notif-*'
journalctl -u notif-run-due-tasks.service --since today --no-pager
```

`./deploy.sh` removes the legacy user crontab entry for the exact
`docker compose -f compose.yaml exec -T backend python manage.py run_due_tasks`
command if it is present.

## Unattended OS Maintenance

Debian's `unattended-upgrades` package is enabled on the host. Keep Debian's
default allowed origins in `/etc/apt/apt.conf.d/50unattended-upgrades`; this
repo only adds local timing and reboot policy.

`./deploy.sh` installs the repo policy when `unattended-upgrade` is available.
For bootstrap or repair, run:

```bash
sudo apt update
sudo apt install -y unattended-upgrades apt-listchanges
cd /home/luka/notif
sudo install -m 0644 deploy/apt/52unattended-upgrades-notif /etc/apt/apt.conf.d/52unattended-upgrades-notif
sudo systemctl enable --now apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service
sudo unattended-upgrade --dry-run --debug
```

The policy performs daily unattended upgrades for whatever origins Debian's
base config allows, removes stale kernels and new unused dependencies, and
reboots at `04:30` only when a package requests reboot.

Do not enable unattended upgrades for third-party package origins casually.
Docker Engine upgrades can restart containers; if Docker packages are added to
the allowed origins later, treat that as a deliberate operations change and
check `notif-compose.service` after the first upgrade window.

## Routine Commands

```bash
# Stack status
systemctl status notif-compose.service
docker compose -f /home/luka/notif/compose.yaml --profile prod ps

# Logs
journalctl -u notif-compose.service --no-pager
docker compose -f /home/luka/notif/compose.yaml --profile prod logs -f backend caddy

# Apply app and host config changes
cd /home/luka/notif
./deploy.sh

# Stop/start the app stack without disabling boot
sudo systemctl stop notif-compose.service
sudo systemctl start notif-compose.service
```

## Future Services

Use the same pattern for Hermes, an F-Droid repository publisher, or any other
host workload:

- Store runtime knobs in `/etc/notif/<service>.env`.
- Add a checked-in unit or timer under `deploy/systemd/`.
- Enable it with `systemctl enable --now <unit>`.
- Keep logs in journald or bounded Docker logs.
- Give every queue, timer, retry loop, and generated artifact retention policy
  an explicit cap.

Prefer a separate unit when a workload has its own lifecycle. Prefer a separate
Compose project only when it genuinely needs multiple cooperating containers.
