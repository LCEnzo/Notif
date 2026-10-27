#!/usr/bin/env bash
# Back up the F-Droid signing keys to this PC. Run in Git Bash on Luka's PC:
#   deploy/fdroid/backup-keys.sh
# `notif-apk export-keys` writes the keys to a tar in the VPS home; this copies
# it to ~/Documents/notif-fdroid-keys-<date>.tar, checks it, and shreds the VPS
# copy. Runbook: docs/operations/fdroid_runbook.md
#
# Overridable for tests: NOTIF_SSH_HOST (notif), NOTIF_BACKUP_DIR (~/Documents).
set -Eeuo pipefail

readonly host=${NOTIF_SSH_HOST:-notif}
readonly remote=notif-fdroid-keys.tar
readonly expected=$'fdroid/apk.p12\nfdroid/apk.pass\nfdroid/repo-index.p12\nfdroid/repo-index.pass'
dest=${NOTIF_BACKUP_DIR:-$HOME/Documents}/notif-fdroid-keys-$(date +%F).tar
readonly dest

die() {
  printf 'backup-keys: %s\n' "$*" >&2
  exit 1
}

info() {
  printf 'backup-keys: %s\n' "$*"
}

[[ ! -e $dest && ! -L $dest ]] || die "refused: $dest exists; an earlier backup has that name"

ssh "$host" notif-apk export-keys
scp -q "$host:$remote" "$dest"

# shellcheck disable=SC2029 # $remote is a constant file name; expanding it here is intended
remote_sum=$(ssh "$host" sha256sum "$remote")
remote_sum=${remote_sum%% *}
local_sum=$(sha256sum "$dest")
local_sum=${local_sum%% *}
info "sha256 $remote_sum  $host:$remote"
info "sha256 $local_sum  $dest"
[[ $remote_sum =~ ^[0-9a-f]{64}$ && $remote_sum == "$local_sum" ]] \
  || die "the hashes differ; left both copies in place"

tar -tvf "$dest"
members=$(tar -tf "$dest" | LC_ALL=C sort)
[[ $members == "$expected" ]] || die "the tar does not hold exactly the four key files; left both copies in place"

ssh "$host" shred -u "$remote"
info "backed up to $dest; shredded the copy on $host"
