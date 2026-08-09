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
# Mark session and CSRF cookies as HTTPS-only — browsers won't send
# them over plain HTTP.
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
