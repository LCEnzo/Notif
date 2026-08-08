#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage: notif-log-snapshot [options]

Collect a bounded diagnostic snapshot for the Notif VPS.

Options:
  --since VALUE          Timeframe for docker logs. Default: 24h.
                         Examples: 30m, 6h, 2d, 2026-05-07T00:00:00Z.
  --journal-since VALUE  Timeframe for journalctl. Default: derived from --since
                         for 30m/6h/2d, otherwise same as --since.
  --level VALUE          journalctl priority filter. Default: warning..err.
                         Examples: err, warning..err, info..err.
  --lines N|all         Max lines per noisy section. Default: 160, max: 2000.
                         Use "all" to print all matching lines.
  --section NAME         Section to print: all, os, caddy, backend, status.
                         Can be passed multiple times. Default: all.
  --help                 Show this help.

Examples:
  notif-log-snapshot
  notif-log-snapshot --since 6h --level err
  notif-log-snapshot --section caddy --section backend --since 30m --lines 80
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

SINCE="24h"
DOCKER_SINCE=""
JOURNAL_SINCE=""
LEVEL="warning..err"
LINES=160
SECTIONS=()

while (($#)); do
  case "$1" in
    --since)
      [[ $# -ge 2 ]] || die "--since needs a value"
      SINCE="$2"
      shift 2
      ;;
    --journal-since)
      [[ $# -ge 2 ]] || die "--journal-since needs a value"
      JOURNAL_SINCE="$2"
      shift 2
      ;;
    --level)
      [[ $# -ge 2 ]] || die "--level needs a value"
      LEVEL="$2"
      shift 2
      ;;
    --lines)
      [[ $# -ge 2 ]] || die "--lines needs a value"
      [[ "$2" == "all" || "$2" =~ ^[0-9]+$ ]] || die "--lines must be an integer or all"
      LINES="$2"
      shift 2
      ;;
    --section)
      [[ $# -ge 2 ]] || die "--section needs a value"
      SECTIONS+=("$2")
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

if [[ "$LINES" != "all" ]]; then
  ((LINES > 0)) || die "--lines must be greater than zero"
  if ((LINES > 2000)); then
    LINES=2000
  fi
fi

if [[ -z "$JOURNAL_SINCE" ]]; then
  if [[ "$SINCE" =~ ^([0-9]+)(m|h|d)$ ]]; then
    case "${BASH_REMATCH[2]}" in
      m) JOURNAL_SINCE="${BASH_REMATCH[1]} minutes ago" ;;
      h) JOURNAL_SINCE="${BASH_REMATCH[1]} hours ago" ;;
      d) JOURNAL_SINCE="${BASH_REMATCH[1]} days ago" ;;
    esac
  else
    JOURNAL_SINCE="$SINCE"
  fi
fi

if [[ "$SINCE" =~ ^([0-9]+)d$ ]]; then
  DOCKER_SINCE="$((BASH_REMATCH[1] * 24))h"
else
  DOCKER_SINCE="$SINCE"
fi

ACCESS_SINCE_EPOCH=""
if ACCESS_SINCE_EPOCH_VALUE="$(date -d "$JOURNAL_SINCE" +%s 2>/dev/null)"; then
  ACCESS_SINCE_EPOCH="$ACCESS_SINCE_EPOCH_VALUE"
fi

if ((${#SECTIONS[@]} == 0)); then
  SECTIONS=(all)
fi

want_section() {
  local needle="$1"
  local section
  for section in "${SECTIONS[@]}"; do
    [[ "$section" == "all" || "$section" == "$needle" ]] && return 0
  done
  return 1
}

header() {
  printf '\n=== %s ===\n' "$1"
}

tail_limit() {
  if [[ "$LINES" == "all" ]]; then
    cat
  else
    tail -n "$LINES"
  fi
}

run_journal() {
  if sudo -n true >/dev/null 2>&1; then
    sudo -n journalctl "$@"
  else
    journalctl "$@"
  fi
}

docker_logs() {
  local container="$1"
  shift
  docker logs --since "$DOCKER_SINCE" "$container" 2>&1 "$@"
}

print_status() {
  header "STATUS"
  date -Is
  hostname
  printf 'uptime: '
  uptime
  if command -v docker >/dev/null 2>&1; then
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
    printf '\n'
    for container in notif-backend-1 notif-caddy-1; do
      if docker inspect "$container" >/dev/null 2>&1; then
        docker inspect "$container" \
          --format '{{.Name}} RestartCount={{.RestartCount}} Status={{.State.Status}} StartedAt={{.State.StartedAt}}{{if .State.Health}} Health={{.State.Health.Status}}{{end}}'
      else
        printf '%s not found\n' "$container"
      fi
    done
  else
    printf 'docker: not installed or not in PATH\n'
  fi
  systemctl --failed --no-pager --plain || true
}

print_os() {
  header "OS_WARN_ERR"
  if [[ "$LINES" == "all" ]]; then
    run_journal --since "$JOURNAL_SINCE" -p "$LEVEL" --no-pager || true
  else
    run_journal --since "$JOURNAL_SINCE" -p "$LEVEL" --no-pager -n "$LINES" || true
  fi

  header "DOCKER_DAEMON_WARN_ERR"
  if [[ "$LINES" == "all" ]]; then
    run_journal -u docker -u containerd --since "$JOURNAL_SINCE" -p "$LEVEL" --no-pager || true
  else
    run_journal -u docker -u containerd --since "$JOURNAL_SINCE" -p "$LEVEL" --no-pager -n "$LINES" || true
  fi
}

print_caddy() {
  header "CADDY_STATUS_COUNTS"
  docker_logs notif-caddy-1 | grep -Eo '"status":[0-9][0-9][0-9]' | sort | uniq -c | sort -nr || true

  header "CADDY_WARN_ERROR"
  docker_logs notif-caddy-1 \
    | grep -Ei '"level":"(warn|error)"|panic|exception|certificate|tls|error' \
    | tail_limit || true

  header "CADDY_ACCESS_4XX_5XX"
  docker exec notif-caddy-1 sh -c \
    'if [ -f /var/log/caddy/access.json ]; then cat /var/log/caddy/access.json; else echo "no access log found"; fi' \
    | grep -E '"status":(4|5)[0-9][0-9]' \
    | awk -v since="$ACCESS_SINCE_EPOCH" 'since == "" { print; next } { line = $0; sub(/^.*"ts":/, ""); sub(/\..*$/, ""); if (($0 + 0) >= since) print line }' \
    | tail_limit || true
}

print_backend() {
  header "BACKEND_STATUS_COUNTS"
  docker_logs notif-backend-1 | grep -Eo '" [1-5][0-9][0-9] ' | sort | uniq -c | sort -nr || true

  header "BACKEND_WARN_ERROR"
  docker_logs notif-backend-1 \
    | grep -Ei 'error|exception|traceback|warning|critical|failed|forbidden|bad request|server error' \
    | tail_limit || true

  header "BACKEND_RECENT_NON_HEALTH"
  docker_logs notif-backend-1 | grep -Ev 'monitoring/health' | tail_limit || true
}

for section in "${SECTIONS[@]}"; do
  case "$section" in
    all|status|os|caddy|backend) ;;
    *) die "unknown section: $section" ;;
  esac
done

if want_section status; then
  print_status
fi
if want_section os; then
  print_os
fi
if want_section caddy; then
  print_caddy
fi
if want_section backend; then
  print_backend
fi
