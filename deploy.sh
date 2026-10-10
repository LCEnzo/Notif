#!/bin/sh
set -eu

# --apk: after the web deploy, build and publish the APK of the deployed commit.
# --fdroid-restore <tar>: restore the F-Droid signing keys from a backup.
# See deploy/fdroid/notif-apk and docs/operations/fdroid_runbook.md.
usage() {
    echo "Usage: $0 [--apk] [--fdroid-restore <backup tar>]" >&2
    exit 2
}
BUILD_APK=false
FDROID_RESTORE=
while [ $# -gt 0 ]; do
    case $1 in
        --apk) BUILD_APK=true ;;
        --fdroid-restore)
            [ $# -ge 2 ] || usage
            case $2 in
                /*) FDROID_RESTORE=$2 ;;
                *) FDROID_RESTORE=$PWD/$2 ;;
            esac
            shift
            ;;
        *) usage ;;
    esac
    shift
done

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
    sudo_cmd systemctl enable notif-compose.service notif-run-due-tasks.timer
    sudo_cmd systemctl reload-or-restart notif-compose.service
    sudo_cmd systemctl start notif-run-due-tasks.timer
}

sync_caddy_config() {
    # The Caddyfile is a single-file bind mount. git pull replaces files by
    # rename, so a running container keeps reading the old inode — even
    # `caddy reload` re-reads that stale content. Compare what the container
    # actually sees against the checkout and restart to rebind when they
    # differ. exec stderr is discarded on purpose: a stopped container makes
    # the probe differ, and the restart below is the remedy either way.
    if docker compose -f compose.yaml --profile prod exec -T caddy cat /etc/caddy/Caddyfile 2>/dev/null | cmp -s - Caddyfile; then
        return
    fi
    echo "=== Caddy config drifted from checkout; restarting caddy to rebind the mount ==="
    docker compose -f compose.yaml --profile prod restart caddy
}

remove_legacy_cron_entry() {
    legacy_command="docker compose -f compose.yaml exec -T backend python manage.py run_due_tasks"
    if [ "$(id -u)" -eq 0 ]; then
        deploy_user=$(stat -c '%U' "$SCRIPT_DIR")
        if [ -z "$deploy_user" ] || [ "$deploy_user" = "UNKNOWN" ]; then
            echo "ERROR: Could not determine the deploy checkout owner for cron cleanup." >&2
            exit 1
        fi
        current_crontab=$(crontab -u "$deploy_user" -l 2>/dev/null || true)
    else
        deploy_user=$(id -un)
        current_crontab=$(crontab -l 2>/dev/null || true)
    fi

    if printf '%s\n' "$current_crontab" | grep -F "$legacy_command" >/dev/null; then
        echo "=== Removing legacy run_due_tasks crontab entry for $deploy_user ==="
        if [ "$(id -u)" -eq 0 ]; then
            printf '%s\n' "$current_crontab" | grep -Fv "$legacy_command" | crontab -u "$deploy_user" -
        else
            printf '%s\n' "$current_crontab" | grep -Fv "$legacy_command" | crontab -
        fi
    fi
}

# Inject into backend/.env so Compose picks it up at runtime.
set_env_value VERSION "$APP_VERSION" backend/.env
set_env_value GIT_HASH "$GIT_HASH" backend/.env

# Build with build arg so the image ENV has the hash as fallback.
docker compose -f compose.yaml build --build-arg GIT_HASH="$GIT_HASH"

# Install host configuration, then let systemd own the Compose lifecycle.
sync_host_config
sync_caddy_config
remove_legacy_cron_entry

echo ""
echo "=== Deploy complete ==="
echo "Verify: curl https://notif.lcenzo.com/api/v1/monitoring/status/"

banner() {
    echo "" >&2
    echo "################################################################" >&2
    printf '  %s\n' "$@" >&2
    echo "################################################################" >&2
}

# F-Droid runs after the web deploy, so its failures cannot block or undo it.
# They still make the exit status 1: the host did not fully converge.
echo ""
echo "=== F-Droid host setup ==="
if [ -n "$FDROID_RESTORE" ]; then
    set -- --restore "$FDROID_RESTORE"
else
    set --
fi
if ! deploy/fdroid/notif-apk setup "$@"; then
    skipped=
    [ "$BUILD_APK" = false ] || skipped=" The APK build was skipped."
    banner "F-DROID HOST SETUP FAILED (see the output above).$skipped" \
        "The web deploy above completed and stays in place." \
        "Fix the cause, then run ./deploy.sh again."
    exit 1
fi

if [ "$BUILD_APK" = true ]; then
    DEPLOYED_SHA=$(git rev-parse HEAD)
    echo ""
    echo "=== Building and publishing the APK for $GIT_HASH ==="
    if ! deploy/fdroid/notif-apk build "$DEPLOYED_SHA"; then
        banner "APK BUILD OR PUBLISH FAILED for $GIT_HASH" \
            "The web deploy above completed and stays in place." \
            "Retry with: deploy/fdroid/notif-apk build $DEPLOYED_SHA"
        exit 1
    fi
fi
