# Publish image for the Notif F-Droid repo: verifies an APK and signs the index.
# Used by `notif-apk publish`, and for keytool by `notif-apk setup` and
# `export-keys`; see docs/operations/fdroid_runbook.md.
FROM debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    fdroidserver=2.4.2-1 \
    apksigner=35.0.2-1 \
    unzip \
  && rm -rf /var/lib/apt/lists/*
