# ── Flutter web build ─────────────────────────────────────────────
# Builds the Notif Flutter frontend for web deployment.
#
# Two stages: build → export. The export stage copies only the built
# web assets to /image-dist (inside the image). At runtime, the
# entrypoint copies them into the mounted /web-dist volume so Caddy
# can serve them. This avoids Docker's first-time-only volume copy
# behavior — every deploy refreshes the volume.
#
# The API_URL dart-define points to the same-origin /api/v1 path because
# the frontend and backend share a single domain in production.
# ──────────────────────────────────────────────────────────────────

FROM ghcr.io/cirruslabs/flutter:stable AS build

ARG GIT_HASH=dev

WORKDIR /app

# Cache pub dependencies separately from source changes.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

# --dart-define injects the production API base URL.
# canvaskit is the default web renderer since Flutter 3.22.
RUN flutter build web --release \
    --dart-define=API_URL=/api/v1 \
    --dart-define=GIT_HASH=$GIT_HASH

# Export stage — minimal image. Assets stay in /image-dist.
# The entrypoint copies them into the shared volume at runtime.
FROM alpine:3.21

COPY --from=build /app/build/web /image-dist
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
