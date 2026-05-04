#!/bin/sh
# ── Frontend asset deploy entrypoint ──────────────────────────────
# Copies built web assets from the immutable /image-dist (inside the
# Docker image) into the mounted /web-dist named volume. This ensures
# every docker compose up refreshes the volume with the current build.
# ──────────────────────────────────────────────────────────────────
set -e

echo "Deploying frontend assets to shared volume..."
rm -rf /web-dist/*
cp -r /image-dist/* /web-dist/
echo "Done. $(find /web-dist -type f | wc -l) files deployed."
