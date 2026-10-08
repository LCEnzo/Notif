#!/usr/bin/env bash
# Signing key operations inside the notif-apk publish image, for `notif-apk
# setup` and `notif-apk export-keys`. The key directory is mounted at /keys.
#
#   inspect         print "absent", "partial <files present>", or
#                   "present <APK cert SHA-256> <repo index cert SHA-256>"
#   generate        create both keys; refuses if any key file exists
#   restore <tar>   install the keys from a backup tar; if APK_CERT_SHA256
#                   and REPO_CERT_SHA256 are set, only when they match
#   archive         write a backup tar (fdroid/<file>) to stdout
set -Eeuo pipefail

readonly keys=/keys
readonly stage=/keys/.staging
readonly files=(apk.p12 apk.pass repo-index.p12 repo-index.pass)

die() {
  printf 'notif-apk keys: %s\n' "$*" >&2
  exit 1
}

# cert_sha256 <dir> <keystore name> <alias>: SHA-256 of the DER certificate.
cert_sha256() {
  local out
  out=$(keytool -exportcert -keystore "$1/$2.p12" -alias "$3" -storepass:file "$1/$2.pass" | sha256sum) || return 1
  printf '%s' "${out%% *}"
}

present_files() {
  local f
  for f in "${files[@]}"; do
    if [[ -e $keys/$f || -L $keys/$f ]]; then
      printf '%s\n' "$f"
    fi
  done
}

# Prints "<APK cert SHA-256> <repo index cert SHA-256>" of the key set in <dir>.
digests() {
  local dir=$1 f apk repo
  for f in "${files[@]}"; do
    [[ -f $dir/$f && ! -L $dir/$f ]] || die "$f is not a regular file"
  done
  apk=$(cert_sha256 "$dir" apk notif-apk) || die "cannot read apk.p12 with apk.pass"
  repo=$(cert_sha256 "$dir" repo-index notif-repo) || die "cannot read repo-index.p12 with repo-index.pass"
  printf '%s %s\n' "$apk" "$repo"
}

refuse_if_any_present() {
  local present
  mapfile -t present < <(present_files)
  ((${#present[@]} == 0)) || die "refusing: the key directory already holds ${present[*]}"
}

new_stage() {
  rm -rf -- "$stage"
  mkdir -m 0700 -- "$stage"
  trap 'rm -rf -- "$stage"' EXIT
}

# Hard links, because ln never replaces an existing file.
install_from() {
  local dir=$1 f
  chmod 0600 -- "${files[@]/#/$dir/}"
  for f in "${files[@]}"; do
    ln -- "$dir/$f" "$keys/$f"
  done
}

inspect() {
  local present out
  mapfile -t present < <(present_files)
  if ((${#present[@]} == 0)); then
    echo absent
  elif ((${#present[@]} < ${#files[@]})); then
    echo "partial ${present[*]}"
  else
    out=$(digests "$keys")
    echo "present $out"
  fi
}

generate() {
  refuse_if_any_present
  new_stage
  umask 077
  head -c 32 /dev/urandom | base64 -w0 >"$stage/apk.pass"
  head -c 32 /dev/urandom | base64 -w0 >"$stage/repo-index.pass"
  keytool -genkeypair -keystore "$stage/apk.p12" -storetype pkcs12 -alias notif-apk \
    -keyalg RSA -keysize 4096 -sigalg SHA256withRSA -validity 10000 \
    -dname "CN=Notif APK" -storepass:file "$stage/apk.pass" -keypass:file "$stage/apk.pass"
  keytool -genkeypair -keystore "$stage/repo-index.p12" -storetype pkcs12 -alias notif-repo \
    -keyalg RSA -keysize 4096 -sigalg SHA256withRSA -validity 10000 \
    -dname "CN=notif-repo, OU=F-Droid" -storepass:file "$stage/repo-index.pass" -keypass:file "$stage/repo-index.pass"
  install_from "$stage"
}

restore() {
  local tar=$1 apk_pin=${APK_CERT_SHA256:-} repo_pin=${REPO_CERT_SHA256:-} out apk repo
  [[ -f $tar ]] || die "not a file: $tar"
  if [[ -n $apk_pin || -n $repo_pin ]]; then
    [[ $apk_pin =~ ^[0-9a-f]{64}$ && $repo_pin =~ ^[0-9a-f]{64}$ ]] || die "set both pins or neither"
  fi
  refuse_if_any_present
  new_stage
  umask 077
  tar -xf "$tar" -C "$stage" --no-same-owner --no-same-permissions "${files[@]/#/fdroid/}" \
    || die "the backup does not hold fdroid/{apk.p12,apk.pass,repo-index.p12,repo-index.pass}; installed nothing"
  out=$(digests "$stage/fdroid")
  read -r apk repo <<<"$out"
  if [[ -n $apk_pin ]]; then
    [[ $apk == "$apk_pin" ]] \
      || die "the backup's APK cert SHA-256 is $apk, the pin is $apk_pin; installed nothing"
    [[ $repo == "$repo_pin" ]] \
      || die "the backup's repo index cert SHA-256 is $repo, the pin is $repo_pin; installed nothing"
  fi
  install_from "$stage/fdroid"
}

archive() {
  local f
  for f in "${files[@]}"; do
    [[ -f $keys/$f && ! -L $keys/$f ]] || die "$f is not a regular file"
  done
  tar -C "$keys" -cf - --transform='s,^,fdroid/,' "${files[@]}"
}

case ${1:-} in
  inspect | generate | archive)
    (($# == 1)) || die "usage: container-keys.sh $1"
    "$1"
    ;;
  restore)
    (($# == 2)) || die "usage: container-keys.sh restore <tar>"
    restore "$2"
    ;;
  *)
    die "usage: container-keys.sh inspect | generate | restore <tar> | archive"
    ;;
esac
