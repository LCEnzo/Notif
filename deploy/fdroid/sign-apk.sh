#!/usr/bin/env bash
# Sign a Notif release APK with the APK key, replacing the debug signature the
# release build carries, and verify the result.
#
# Usage:
#   APK_KS=<keystore.p12> APK_KS_PASS_FILE=<password file> deploy/fdroid/sign-apk.sh <in.apk> <out.apk>
#
# Under `notif-apk build` it runs in a container of its own with --network
# none, after the build container has exited. apksigner reads the password
# from its file, so it never enters an environment or a command line.
set -Eeuo pipefail

readonly key_alias=notif-apk
# The pinned Flutter base image ships 36.0.0; build.Dockerfile adds 35.0.0 for AGP.
readonly build_tools=36.0.0

die() {
  printf 'sign-apk: %s\n' "$*" >&2
  exit 1
}

(($# == 2)) || die "usage: sign-apk.sh <in.apk> <out.apk>"
in_apk=$1
out_apk=$2
[[ -f $in_apk ]] || die "not a file: $in_apk"
keystore=${APK_KS:?APK_KS must name the APK keystore}
[[ -f $keystore ]] || die "APK_KS is not a file: $keystore"
pass_file=${APK_KS_PASS_FILE:?APK_KS_PASS_FILE must name the keystore password file}
[[ -f $pass_file ]] || die "APK_KS_PASS_FILE is not a file: $pass_file"
apksigner=${ANDROID_HOME:?ANDROID_HOME must point to the Android SDK}/build-tools/$build_tools/apksigner
[[ -x $apksigner ]] || die "apksigner not found at $apksigner"

"$apksigner" sign \
  --ks "$keystore" \
  --ks-key-alias "$key_alias" \
  --ks-pass "file:$pass_file" \
  --v4-signing-enabled false \
  --out "$out_apk" \
  "$in_apk"
"$apksigner" verify "$out_apk"

printf 'sign-apk: signed %s\n' "$out_apk"
