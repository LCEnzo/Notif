# ruff: noqa: F403, F405
"""Development settings: DEBUG on, silk profiling, loopback CORS/CSRF, fast password hashing."""

from notif.config import settings
from notif.settings_base import *

DEBUG = True

INSTALLED_APPS += ["silk"]
MIDDLEWARE.insert(1, "silk.middleware.SilkyMiddleware")

# Dev whitelist: loopback only. A regex rather than a literal list because the
# Flutter web dev server picks a random port on every `flutter run`.
CORS_ALLOWED_ORIGIN_REGEXES = [r"^https?://(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$"]

# Django's CSRF origin comparison is port-exact, and CORS_ALLOWED_ORIGIN_REGEXES
# above does not feed it — so the loopback wildcard that lets the Flutter dev
# server talk to us is not enough to let it POST. Pin the dev web port
# (`flutter run -d chrome --web-port=$DEV_WEB_PORT`) and trust exactly that.
CSRF_TRUSTED_ORIGINS += [
	f"http://localhost:{settings.DEV_WEB_PORT}",
	f"http://127.0.0.1:{settings.DEV_WEB_PORT}",
]

# https://stackoverflow.com/questions/18273110/django-make-password-too-slow-for-creating-large-list-of-users-programatically
# https://docs.djangoproject.com/en/4.2/topics/auth/passwords/
# This cuts down user creation time from ~270ms to 2.2ms on my laptop, but compromises security.
PASSWORD_HASHERS = [
	"django.contrib.auth.hashers.MD5PasswordHasher",
	"django.contrib.auth.hashers.PBKDF2PasswordHasher",
	"django.contrib.auth.hashers.PBKDF2SHA1PasswordHasher",
	"django.contrib.auth.hashers.Argon2PasswordHasher",
	"django.contrib.auth.hashers.BCryptSHA256PasswordHasher",
	"django.contrib.auth.hashers.ScryptPasswordHasher",
]

# In addition to console output, write a rotating file under backend/logs/ so
# the developer gets persistent logs without piping runserver through tee.
_LOG_DIR = BASE_DIR / "logs"
_LOG_DIR.mkdir(exist_ok=True)
LOGGING["handlers"]["file"] = {
	"class": "logging.handlers.RotatingFileHandler",
	"filename": str(_LOG_DIR / "dev.log"),
	"maxBytes": 5_000_000,
	"backupCount": 3,
	"formatter": "default",
}
LOGGING["root"]["handlers"].append("file")
LOGGING["root"]["level"] = "DEBUG"
