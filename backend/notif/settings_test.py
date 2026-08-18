# ruff: noqa: F403, F405
"""Test settings: throttles wired but rate-free, console-only logging, fast password hashing."""

from notif.config import Environment
from notif.config import settings as _config
from notif.settings_base import *

# A test suite must never touch a production deployment target.
if _config.NOTIF_ENV == Environment.PRODUCTION:
	raise RuntimeError("Refusing to run the test suite with NOTIF_ENV=production.")

DEBUG = False
TESTING = True

# Throttle classes stay wired so tests exercise the prod-shaped request path: a
# None rate is a per-scope no-op, while an undeclared scope still raises
# ImproperlyConfigured.
REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"] = dict.fromkeys(REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"])

# Console only — test runs must not write SystemEvent rows or log files.
LOGGING["root"]["handlers"] = ["console"]

# Mail is captured in mail.outbox instead of reaching SMTP or the console.
EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"

# Config fails the bootstrap login closed; the suite exercises its flow.
DEV_BOOTSTRAP_LOGIN_ENABLED = True

# MD5-first keeps user creation fast enough for the suite.
PASSWORD_HASHERS = [
	"django.contrib.auth.hashers.MD5PasswordHasher",
	"django.contrib.auth.hashers.PBKDF2PasswordHasher",
	"django.contrib.auth.hashers.PBKDF2SHA1PasswordHasher",
	"django.contrib.auth.hashers.Argon2PasswordHasher",
	"django.contrib.auth.hashers.BCryptSHA256PasswordHasher",
	"django.contrib.auth.hashers.ScryptPasswordHasher",
]
