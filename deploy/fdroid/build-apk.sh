#!/usr/bin/env bash
# Build the Notif arm64 release APK and sign it with the APK key.
#
# Usage, from the repo root:
#   APK_KS=<keystore.p12> APK_KS_PASS=<password> deploy/fdroid/build-apk.sh <versionCode> <short sha>
#
# Writes out/notif-<versionCode>-<short sha>.apk. The two dart-defines are fixed
# and no other arguments are accepted (plan Recommendation 6). Runs in the
# notif-apk build image and on a GitHub runner with Flutter and the Android SDK.
set -Eeuo pipefail

readonly api_url=https://notif.lcenzo.com/api/v1
readonly key_alias=notif-apk
readonly build_tools=36.0.0
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
keystore=${APK_KS:?APK_KS must name the APK keystore}
[[ -f $keystore ]] || die "APK_KS is not a file: $keystore"
# Kept out of the environment of the build; only apksigner gets it.
ks_pass=${APK_KS_PASS:?APK_KS_PASS must hold the APK keystore password}
unset APK_KS_PASS
apksigner=${ANDROID_HOME:?ANDROID_HOME must point to the Android SDK}/build-tools/$build_tools/apksigner
[[ -x $apksigner ]] || die "apksigner not found at $apksigner"

out_dir=$PWD/out
out_apk=$out_dir/notif-$version_code-$short_sha.apk
unsigned_apk=$PWD/frontend/build/app/outputs/flutter-apk/app-release.apk
mkdir -p "$out_dir"
rm -f "$unsigned_apk"

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

# apksigner replaces the debug signature the release build carries.
APK_KS_PASS=$ks_pass "$apksigner" sign \
  --ks "$keystore" \
  --ks-key-alias "$key_alias" \
  --ks-pass env:APK_KS_PASS \
  --v4-signing-enabled false \
  --out "$out_apk" \
  "$unsigned_apk"

printf 'build-apk: signed %s\n' "$out_apk"
