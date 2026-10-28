#!/usr/bin/env bash
# Build the Notif arm64 release APK. It carries the debug signature
# (frontend/android/app/build.gradle); sign-apk.sh replaces it with the APK key.
#
# Usage, from the repo root:
#   deploy/fdroid/build-apk.sh <versionCode> <short sha>
#
# Writes out/notif-<versionCode>-<short sha>-debug-signed.apk. The two
# dart-defines are fixed and no other arguments are accepted (plan
# Recommendation 6). Needs no key, so the build's code never reaches one. Runs
# in the notif-apk build image and on a GitHub runner with Flutter and the
# Android SDK.
set -Eeuo pipefail

readonly api_url=https://notif.lcenzo.com/api/v1
readonly max_version_code=2100000000

die() {
  printf 'build-apk: %s\n' "$*" >&2
  exit 1
}

(($# == 2)) || die "usage: build-apk.sh <versionCode> <short sha>"
version_code=$1
short_sha=$2
if ! [[ $version_code =~ ^[1-9][0-9]{0,9}$ ]] || ((version_code > max_version_code)); then
  die "versionCode must be an integer in 1..$max_version_code, got '$version_code'"
fi
[[ $short_sha =~ ^[0-9a-f]{7,40}$ ]] || die "short sha must be 7-40 lowercase hex digits, got '$short_sha'"

[[ -f frontend/pubspec.yaml ]] || die "run from the repo root (frontend/pubspec.yaml not found)"

out_dir=$PWD/out
out_apk=$out_dir/notif-$version_code-$short_sha-debug-signed.apk
release_apk=$PWD/frontend/build/app/outputs/flutter-apk/app-release.apk
mkdir -p "$out_dir"
rm -f "$release_apk"

(
  cd frontend
  flutter --version
  flutter pub get --enforce-lockfile
  flutter build apk --release \
    --target-platform android-arm64 \
    --build-number "$version_code" \
    --dart-define=API_URL="$api_url" \
    --dart-define=GIT_HASH="$short_sha"
)

cp "$release_apk" "$out_apk"
printf 'build-apk: built %s\n' "$out_apk"
