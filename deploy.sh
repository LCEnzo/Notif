#!/bin/sh
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

echo "=== Pulling latest code ==="
git pull

GIT_HASH=$(git rev-parse --short HEAD)
APP_VERSION=$(awk -F': *' '$1 == "version" { print $2; exit }' frontend/pubspec.yaml)
APP_VERSION=${APP_VERSION%%+*}
if [ -z "$APP_VERSION" ]; then
    echo "ERROR: Could not read app version from frontend/pubspec.yaml" >&2
    exit 1
fi
echo "=== Deploying commit: $GIT_HASH (version $APP_VERSION) ==="

set_env_value() {
    key=$1
    value=$2
    file=$3
    if grep -q "^$key=" "$file"; then
        sed -i "s/^$key=.*/$key=$value/" "$file"
    else
        printf "\n%s=%s\n" "$key" "$value" >> "$file"
    fi
}

sudo_cmd() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

sync_host_config() {
    echo "=== Syncing host config ==="

    sudo_cmd install -d -m 0755 /etc/notif
    printf 'NOTIF_DEPLOY_DIR=%s\nNOTIF_COMPOSE_FILE=compose.yaml\nNOTIF_COMPOSE_PROFILE=prod\n' "$SCRIPT_DIR" \
        | sudo_cmd tee /etc/notif/notif-compose.env >/dev/null
    sudo_cmd chmod 0644 /etc/notif/notif-compose.env

    sudo_cmd install -m 0644 deploy/systemd/notif-compose.service /etc/systemd/system/notif-compose.service
    sudo_cmd install -m 0644 deploy/systemd/notif-run-due-tasks.service /etc/systemd/system/notif-run-due-tasks.service
    sudo_cmd install -m 0644 deploy/systemd/notif-run-due-tasks.timer /etc/systemd/system/notif-run-due-tasks.timer

    if command -v unattended-upgrade >/dev/null 2>&1; then
        sudo_cmd install -m 0644 deploy/apt/52unattended-upgrades-notif /etc/apt/apt.conf.d/52unattended-upgrades-notif
        sudo_cmd systemctl enable --now apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service
    else
        echo "WARNING: unattended-upgrades is not installed; skipping apt unattended-upgrades policy." >&2
    fi

    sudo_cmd systemctl daemon-reload
    sudo_cmd systemctl enable --now docker.service
    sudo_cmd systemctl enable --now notif-compose.service
    sudo_cmd systemctl enable --now notif-run-due-tasks.timer
}

remove_legacy_cron_entry() {
    legacy_command="docker compose -f compose.yaml exec -T backend python manage.py run_due_tasks"
    if crontab -l 2>/dev/null | grep -F "$legacy_command" >/dev/null; then
        echo "=== Removing legacy run_due_tasks crontab entry ==="
        crontab -l | grep -Fv "$legacy_command" | crontab -
    fi
}

# Inject into backend/.env so Compose picks it up at runtime.
set_env_value VERSION "$APP_VERSION" backend/.env
set_env_value GIT_HASH "$GIT_HASH" backend/.env

# Build with build arg so the image ENV has the hash as fallback.
docker compose -f compose.yaml build --build-arg GIT_HASH="$GIT_HASH"

# Start backend + Caddy (prod profile enables Caddy).
docker compose -f compose.yaml --profile prod up -d

sync_host_config
remove_legacy_cron_entry

echo ""
echo "=== Deploy complete ==="
echo "Verify: curl https://notif.lcenzo.com/api/v1/monitoring/status/"
