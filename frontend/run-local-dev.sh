#!/usr/bin/env bash
set -eu

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
backend_env="$repo_root/backend/.env"

backend_port="8000"

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
    esac
  done < "$backend_env"
fi

api_url="http://localhost:${backend_port}/api/v1"

exec flutter run --dart-define="API_URL=${api_url}" "$@"
