# ── Flutter web build ─────────────────────────────────────────────
# Builds the Notif Flutter frontend for web deployment.
#
# Two stages: build → export. The export stage copies only the built
# web assets so the final image is small and the output can be mounted
# as a named volume for Caddy to serve.
#
# The API_URL dart-define points to the same-origin /api/v1 path because
# the frontend and backend share a single domain in production.
# ──────────────────────────────────────────────────────────────────

FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# Cache pub dependencies separately from source changes.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

# Web-specific: canvaskit renderer for consistent text rendering across
# browsers, --dart-define injects the production API base URL.
RUN flutter build web --release \
    --dart-define=API_URL=/api/v1 \
    --web-renderer canvaskit

# Export stage — minimal image containing only the built web assets.
FROM alpine:3.21
COPY --from=build /app/build/web /dist
