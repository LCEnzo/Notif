# ruff: noqa: F403
"""Production settings: DEBUG off plus HTTPS hardening."""

from notif.settings_base import *

DEBUG = False

# ── production security hardening ────────────────────────────
# Redirect all HTTP to HTTPS. Requires a reverse proxy (nginx/Caddy)
# that sets the X-Forwarded-Proto header.
SECURE_SSL_REDIRECT = True
# Tell Django to trust the X-Forwarded-Proto header from the proxy.
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
# Tell browsers to only use HTTPS for this domain for 1 year.
SECURE_HSTS_SECONDS = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
# security.W021 asks for SECURE_HSTS_PRELOAD. Preloading is impossible by design here:
# the preload list takes only a registrable domain (lcenzo.com, never notif.lcenzo.com),
# and preloading lcenzo.com would pin HTTPS on every sibling host for months. HSTS is
# deliberately scoped to notif.*: Django adds it to the responses it serves (/api,
# /admin); Caddy's static and SPA responses, and its apex/wildcard blocks, send none.
SILENCED_SYSTEM_CHECKS = ["security.W021"]
# Mark session and CSRF cookies as HTTPS-only — browsers won't send
# them over plain HTTP.
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
