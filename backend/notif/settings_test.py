# ruff: noqa: F403, F405
"""Test settings: throttling off, console-only logging, fast password hashing."""

from notif.settings_base import *

DEBUG = False
TESTING = True

# Rate limits would break the test suite.
REST_FRAMEWORK["DEFAULT_THROTTLE_CLASSES"] = []

# Console only — test runs must not write SystemEvent rows or log files.
LOGGING["root"]["handlers"] = ["console"]

# MD5-first keeps user creation fast enough for the suite.
PASSWORD_HASHERS = [
	"django.contrib.auth.hashers.MD5PasswordHasher",
	"django.contrib.auth.hashers.PBKDF2PasswordHasher",
	"django.contrib.auth.hashers.PBKDF2SHA1PasswordHasher",
	"django.contrib.auth.hashers.Argon2PasswordHasher",
	"django.contrib.auth.hashers.BCryptSHA256PasswordHasher",
	"django.contrib.auth.hashers.ScryptPasswordHasher",
]
