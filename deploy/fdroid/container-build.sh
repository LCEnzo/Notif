#!/usr/bin/env bash
# Entry point of the build container under `notif-apk build`. Builds a copy of
# the read-only worktree at /src, so nothing the build writes lands on the host
# except the signed APK in /out, then reports the container's memory use.
#
# Usage: container-build.sh <versionCode> <short sha>
set -Eeuo pipefail

readonly cgroup=/sys/fs/cgroup
readonly anon_peak_file=/tmp/anon-peak

# memory.peak includes page cache, which fills up to the limit, so also sample
# anonymous memory (the JVM and Dart heaps): cgroup v2 keeps no peak for it.
sample_anon() {
  local max=0 cur
  while sleep 2; do
    cur=$(sed -n 's/^anon //p' "$cgroup/memory.stat") || return 0
    if ((cur > max)); then
      max=$cur
      printf '%s\n' "$max" >"$anon_peak_file"
    fi
  done
}

mib() {
  if [[ -n $1 ]]; then
    printf '%s MiB' "$(($1 / 1048576))"
  else
    printf 'unknown'
  fi
}

report_memory() {
  local peak anon events
  peak=$(cat "$cgroup/memory.peak" 2>/dev/null) || peak=
  anon=$(cat "$anon_peak_file" 2>/dev/null) || anon=
  events=$(tr '\n' ' ' <"$cgroup/memory.events" 2>/dev/null) || events=unknown
  printf 'notif-apk: build memory: anon peak %s (sampled every 2 s), memory.peak %s (includes page cache); memory.events: %s\n' \
    "$(mib "$anon")" "$(mib "$peak")" "$events"
}

if (($# != 2)); then
  printf 'usage: container-build.sh <versionCode> <short sha>\n' >&2
  exit 1
fi

# This script is PID 1, which ignores signals it has no handler for. Exiting
# PID 1 ends the container, and with it the build.
trap report_memory EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
sample_anon &

mkdir /build
cp -a /src/. /build/
# The worktree's .git file points outside the container.
rm -f /build/.git
ks_pass=$(</run/secrets/apk.pass)
cd /build
# In the background so that wait, unlike a foreground command, is interrupted by the traps.
APK_KS=/run/secrets/apk.p12 APK_KS_PASS=$ks_pass nice -n 10 bash /tool/build-apk.sh "$1" "$2" &
wait "$!"
install -m 0644 "out/notif-$1-$2.apk" /out/
