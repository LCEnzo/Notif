# ruff: noqa: F403, F405
"""Execution-mode settings for the test suite.

Layered over the serving-shaped base (``notif.settings``) so tests run
prod-shaped — DEBUG off, real ALLOWED_HOSTS, production exception handling —
while overriding only what a fast, hermetic suite legitimately needs. Selected
deterministically via ``DJANGO_SETTINGS_MODULE`` in pyproject, never inherited
from ambient environment.
"""

from notif.config import Environment
from notif.config import settings as _config
from notif.settings import *

# Make NOTIF_ENV=production + pytest unreachable rather than merely discouraged:
# a suite must never touch a production deployment target.
if _config.NOTIF_ENV == Environment.PRODUCTION:
	raise RuntimeError("Refusing to run the test suite with NOTIF_ENV=production.")

TESTING = True

# DEBUG stays False so tests exercise prod-shaped behaviour. The one serving-only
# default that makes the test client unusable is the HTTPS redirect — every
# request would 301 — so disable exactly that and nothing else.
DEBUG = False
SECURE_SSL_REDIRECT = False

# Fast hasher: user creation drops from ~270ms to ~2ms. Not a security surface
# under test.
PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]

# Mail is captured in mail.outbox instead of reaching SMTP or the console.
EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"

# Default rate limits off: a suite hammers endpoints and DRF's throttle state
# leaks across tests through the cache. Drop the default throttle classes; the
# base rates stay intact for serving, and no view needs a test-mode branch.
REST_FRAMEWORK = {**REST_FRAMEWORK, "DEFAULT_THROTTLE_CLASSES": []}

# Keep domain-event log rows out of the test database.
LOGGING = {**LOGGING, "root": {"handlers": ["console"], "level": "INFO"}}
