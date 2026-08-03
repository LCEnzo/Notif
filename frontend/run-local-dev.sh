#!/usr/bin/env bash
set -eu

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
backend_env="$repo_root/backend/.env"

backend_port="8000"
# Django's CSRF origin check is port-exact and DEBUG settings trust exactly
# this loopback origin, so a web run has to land on it. Keep in sync with
# DEV_WEB_PORT in backend/.env(.example).
web_port="5353"

if [ -f "$backend_env" ]; then
  while IFS='=' read -r raw_key raw_value; do
    key="$(printf '%s' "$raw_key" | tr -d '[:space:]')"

    case "$key" in
      ''|'#'*)
        continue
        ;;
      BACKEND_PORT)
        backend_port="$(printf '%s' "${raw_value:-}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/^["'"'"'"]//; s/["'"'"'"]$//')"
        ;;
      DEV_WEB_PORT)
        web_port="$(printf '%s' "${raw_value:-}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/^["'"'"'"]//; s/["'"'"'"]$//')"
        ;;
    esac
  done < "$backend_env"
fi

api_url="http://localhost:${backend_port}/api/v1"

# --web-port only matters for web targets, where an unpinned random port would
# fail Django's CSRF origin check. It is harmless on other devices.
exec flutter run --dart-define="API_URL=${api_url}" --web-port="${web_port}" "$@"
