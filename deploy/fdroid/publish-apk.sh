#!/usr/bin/env bash
# Verify a signed Notif APK and add it to the F-Droid repo (plan checks 3a-3d).
#
# Runs inside the notif-apk publish image; `notif-apk publish` sets up:
#   /tool                          deploy/fdroid (read-only)
#   /work/repo                     the served repo directory
#   /run/secrets/repo-index.p12    index keystore and its password file (read-only)
#   /run/secrets/repo-index.pass
#   APK_CERT_SHA256, REPO_CERT_SHA256   pinned cert digests from deploy/fdroid/pins
#
# Exit 0: published, or versionCode already published (no-op). Exit 1: refused, or
# publishing failed and repo/ was restored to its state before the run.
set -Eeuo pipefail

readonly app_id=com.lcenzo.notif
readonly api_url=https://notif.lcenzo.com/api/v1
readonly dev_api_host=localhost:8000
readonly repo_key_alias=notif-repo
readonly keep=3
readonly work=/work
readonly repo=$work/repo
readonly secrets=/run/secrets

refuse() {
  printf 'publish: REFUSED: %s\n' "$*" >&2
  exit 1
}

info() {
  printf 'publish: %s\n' "$*"
}

(($# == 1)) || refuse "usage: publish-apk.sh <apk>"
apk=$1
[[ -f $apk ]] || refuse "not a file: $apk"
[[ -d $repo ]] || refuse "repo directory $repo is not mounted"

[[ ${APK_CERT_SHA256:-} =~ ^[0-9a-f]{64}$ ]] || refuse "pin missing: APK cert SHA-256 (deploy/fdroid/pins/apk-cert.sha256)"
[[ ${REPO_CERT_SHA256:-} =~ ^[0-9a-f]{64}$ ]] \
  || refuse "pin missing: repo index cert SHA-256 (deploy/fdroid/pins/repo-index-cert.sha256)"

scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT

REPO_KS_PASS=$(<"$secrets/repo-index.pass")
export REPO_KS_PASS
index_cert=$(keytool -exportcert -keystore "$secrets/repo-index.p12" -alias "$repo_key_alias" \
  -storepass:env REPO_KS_PASS | sha256sum) || refuse "cannot read the repo index key"
index_cert=${index_cert%% *}
[[ $index_cert == "$REPO_CERT_SHA256" ]] \
  || refuse "repo index key cert SHA-256 $index_cert does not match the pin $REPO_CERT_SHA256"

# 3a: signed by exactly one signer, the pinned APK key.
if ! verify_out=$(apksigner verify --verbose --print-certs "$apk" 2>&1); then
  printf '%s\n' "$verify_out" >&2
  refuse "check 3a: apksigner verify failed"
fi
mapfile -t signer_certs < <(sed -nE 's/^Signer #[0-9]+ certificate SHA-256 digest: ([0-9a-f]{64})$/\1/p' <<<"$verify_out")
if ((${#signer_certs[@]} != 1)) || ! grep -qxF 'Number of signers: 1' <<<"$verify_out"; then
  printf '%s\n' "$verify_out" >&2
  refuse "check 3a: expected exactly one signer"
fi
[[ ${signer_certs[0]} == "$APK_CERT_SHA256" ]] \
  || refuse "check 3a: signer cert SHA-256 ${signer_certs[0]} does not match the pin $APK_CERT_SHA256 (debug-signed or wrong key)"
info "check 3a passed: signed by the pinned APK key"

# 3b: the production API URL is compiled in and the dev default is not.
if ! unzip -p "$apk" lib/arm64-v8a/libapp.so >"$scratch/libapp.so" 2>/dev/null || ! [[ -s $scratch/libapp.so ]]; then
  refuse "check 3b: lib/arm64-v8a/libapp.so missing from the APK"
fi
grep -aqF "$api_url" "$scratch/libapp.so" || refuse "check 3b: libapp.so does not contain $api_url"
if grep -aqF "$dev_api_host" "$scratch/libapp.so"; then
  refuse "check 3b: libapp.so contains $dev_api_host"
fi
info "check 3b passed: built against $api_url"

# 3c: versionCode above the newest in the published index; equal is a no-op.
read -r apk_id version_code version_name < <(python3 -c '
import sys
from fdroidserver import common
print(*common.get_apk_id(sys.argv[1]))
' "$apk") || refuse "cannot read the APK manifest"
[[ $apk_id == "$app_id" ]] || refuse "APK is $apk_id, expected $app_id"
[[ $version_code =~ ^[1-9][0-9]*$ ]] || refuse "unexpected versionCode '$version_code'"
newest=$(python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        index = json.load(f)
except FileNotFoundError:
    index = {}
versions = index.get("packages", {}).get(sys.argv[2], {}).get("versions", {}).values()
print(max((v["manifest"]["versionCode"] for v in versions), default=0))
' "$repo/index-v2.json" "$app_id") || refuse "cannot read $repo/index-v2.json"
if ((version_code == newest)); then
  info "check 3c: versionCode $version_code is already published; nothing to do"
  exit 0
fi
((version_code > newest)) \
  || refuse "check 3c: versionCode $version_code is lower than the newest published, $newest"
info "check 3c passed: versionCode $version_code ($version_name) > $newest"

# 3d: never overwrite an existing APK.
target=$repo/${app_id}_$version_code.apk
if [[ -e $target || -L $target ]]; then
  refuse "check 3d: $(basename -- "$target") already exists in repo/"
fi
info "check 3d passed: $(basename -- "$target") is new"

install -d -m 0700 "$work/metadata"
install -m 0600 /tool/config.yml "$work/config.yml"
install -m 0644 "/tool/metadata/$app_id.yml" "$work/metadata/$app_id.yml"

# Keep the newest $keep APKs, counting the new one. Only names this script writes are candidates.
mapfile -t codes < <({
  find "$repo" -maxdepth 1 -type f -name "${app_id}_*.apk" -printf '%f\n'
  printf '%s\n' "${app_id}_$version_code.apk"
} | sed -nE "s/^${app_id//./\\.}_([0-9]+)\\.apk\$/\\1/p" | sort -rn)
prune=("${codes[@]:keep}")

# Everything below changes repo/, so first keep what is needed to put it back:
# a copy of the non-APK files, and the pruned APKs, moved here instead of deleted.
snapshot=$scratch/repo-before
held=$scratch/pruned
mkdir -- "$held"
rsync -a --exclude='/*.apk' "$repo/" "$snapshot/" || refuse "cannot snapshot repo/"
pruned=()

# Runs as an if condition, where set -e is off; every step checks itself.
apply() {
  local code name
  install -m 0644 -- "$apk" "$target" || return 1
  for code in "${prune[@]}"; do
    name=${app_id}_$code.apk
    mv -- "$repo/$name" "$held/$name" || return 1
    pruned+=("$name")
  done
  (cd "$work" && fdroid update) || return 1
}

rollback() {
  local name ok=0
  rm -f -- "$target" || ok=1
  for name in "${pruned[@]}"; do
    mv -- "$held/$name" "$repo/$name" || ok=1
  done
  rsync -a --delete --exclude='/*.apk' "$snapshot/" "$repo/" || ok=1
  return "$ok"
}

if ! apply; then
  rollback || refuse "publish failed, and so did restoring repo/; it is now inconsistent (see the errors above)"
  refuse "publish failed (see the output above); restored repo/ to its state before this run"
fi
for name in "${pruned[@]}"; do
  info "pruned $name"
done
info "published $(basename -- "$target")"
