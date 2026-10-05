"""Base Django settings for notif — everything environment-independent.

The environment is selected exclusively via DJANGO_SETTINGS_MODULE:
``notif.settings_dev``, ``notif.settings_prod``, and ``notif.settings_test``
star-import this module and override explicitly. Nothing here may branch on
DEBUG, test detection, or any other ambient environment value.
"""

from pathlib import Path
from typing import Any

from notif.config import settings

# App code reads settings.TESTING to relax behavior under test (e.g. login
# throttling backoff). Only notif.settings_test sets it to True.
TESTING = False

# Build paths inside the project like this: BASE_DIR / 'subdir'.
BASE_DIR = Path(__file__).resolve().parent.parent

# SECURITY WARNING: keep the secret key used in production secret!
SECRET_KEY = settings.DJANGO_SECRET_KEY

DEV_BOOTSTRAP_LOGIN_ENABLED = settings.DEV_BOOTSTRAP_LOGIN_ENABLED
DEV_BOOTSTRAP_USERNAME = settings.DEV_BOOTSTRAP_USERNAME
DEV_BOOTSTRAP_PASSWORD = settings.DEV_BOOTSTRAP_PASSWORD
DEV_BOOTSTRAP_EMAIL = settings.DEV_BOOTSTRAP_EMAIL
DEV_BOOTSTRAP_NAME = settings.DEV_BOOTSTRAP_NAME

ALLOWED_HOSTS = [host.strip() for host in settings.ALLOWED_HOSTS.split(",") if host.strip()]
# Never allow every origin, not even in dev. Combined with CORS_ALLOW_CREDENTIALS
# below, "*" would hand any page a developer happens to visit credentialed access to
# the dev API — including the dev bootstrap login whenever notif.config enables it.
CORS_ALLOW_ALL_ORIGINS = False
CORS_ALLOWED_ORIGINS = [origin.strip() for origin in settings.CORS_ALLOWED_ORIGINS.split(",") if origin.strip()]
CORS_ALLOWED_ORIGIN_REGEXES: list[str] = []
CORS_ALLOW_CREDENTIALS = True
# The frontend distinguishes our session rejection from an edge-generated 401
# by this challenge. Browsers hide non-safelisted response headers unless CORS
# exposes them explicitly.
CORS_EXPOSE_HEADERS = ["WWW-Authenticate"]
CSRF_TRUSTED_ORIGINS = [origin.strip() for origin in settings.CSRF_TRUSTED_ORIGINS.split(",") if origin.strip()]
DEV_WEB_PORT = settings.DEV_WEB_PORT


# Application definition

INSTALLED_APPS = [
	"django.contrib.admin",
	"django.contrib.auth",
	"django.contrib.contenttypes",
	"django.contrib.sessions",
	"django.contrib.messages",
	"django.contrib.staticfiles",
	"corsheaders",
	"rest_framework",
	"drf_spectacular",
	"accounts",
	"monitoring",
	"ops",
]

MIDDLEWARE = [
	"django.middleware.security.SecurityMiddleware",
	"notif.middleware.DevLatencyMiddleware",
	"django.contrib.sessions.middleware.SessionMiddleware",
	"corsheaders.middleware.CorsMiddleware",
	"django.middleware.common.CommonMiddleware",
	"django.middleware.csrf.CsrfViewMiddleware",
	"django.contrib.auth.middleware.AuthenticationMiddleware",
	"django.contrib.messages.middleware.MessageMiddleware",
	"django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "notif.urls"

TEMPLATES = [
	{
		"BACKEND": "django.template.backends.django.DjangoTemplates",
		"DIRS": [],
		"APP_DIRS": True,
		"OPTIONS": {
			"context_processors": [
				"django.template.context_processors.debug",
				"django.template.context_processors.request",
				"django.contrib.auth.context_processors.auth",
				"django.contrib.messages.context_processors.messages",
			],
		},
	},
]

WSGI_APPLICATION = "notif.wsgi.application"


# Database
# https://docs.djangoproject.com/en/4.0/ref/settings/#databases

DATABASES = {
	"default": {
		"ENGINE": "django.db.backends.sqlite3",
		"NAME": settings.SQLITE_PATH,
		# SQLite reports has_select_for_update = False, and Django's compiler
		# silently drops the FOR UPDATE clause rather than raising - so row
		# locks cannot be relied on here, and concurrent writers can both read
		# the same row before either writes.
		#
		# In the default DEFERRED mode a transaction reads first, holding only a
		# SHARED lock, and asks for a write lock at its first UPDATE. SQLite
		# refuses that upgrade with SQLITE_BUSY *immediately* when another
		# transaction holds the write lock - the busy timeout is not honoured,
		# because waiting could only deadlock. The loser raises "database is
		# locked" (a 500) instead of reaching the grace-window branch that exists
		# for exactly this multi-tab case.
		#
		# IMMEDIATE takes the write lock when the transaction opens, so the
		# second writer waits out the timeout and then finds used_at already set
		# - the conditional-update path the grace window is built on. The cost is
		# that write transactions serialise, which on a single-instance
		# deployment is the right trade. WAL additionally lets reads proceed
		# during a write.
		"OPTIONS": {
			"transaction_mode": "IMMEDIATE",
			"timeout": 20,
			"init_command": "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;",
		},
	}
}

# Password validation
# https://docs.djangoproject.com/en/4.0/ref/settings/#auth-password-validators

# Note the custom validator
AUTH_PASSWORD_VALIDATORS = [
	{
		"NAME": "notif.password_validators.EntropyValidator",
	},
	{
		"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator",
	},
	{
		"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
		"OPTIONS": {
			"min_length": 8,
		},
	},
	{
		"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator",
	},
	{
		"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator",
	},
]

AUTH_USER_MODEL = "accounts.User"

# Internationalization
# https://docs.djangoproject.com/en/4.0/topics/i18n/

LANGUAGE_CODE = "en-us"

TIME_ZONE = "UTC"

USE_I18N = True

USE_TZ = True


# Static files (CSS, JavaScript, Images)
# https://docs.djangoproject.com/en/4.0/howto/static-files/

STATIC_URL = "static/"

# Directory where ``collectstatic`` gathers all static files for production serving.
# In development (runserver), Django serves from each app's ``static/`` dir directly.
# In production, gunicorn/nginx/Caddy serves from this single directory.
STATIC_ROOT = BASE_DIR / settings.STATIC_ROOT
CADDY_ACCESS_LOG_PATH = settings.CADDY_ACCESS_LOG_PATH


# Default primary key field type
# https://docs.djangoproject.com/en/4.0/ref/settings/#default-auto-field

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# REST Framework stuff
_REST_THROTTLE_RATES = {
	"user": "500/hour",
	"anon": "60/min",
	"login": "5/min",
	"register": "3/min",
	# Logout is anonymous (it authenticates by presented token, not by DRF), so
	# this scope keys on the client IP. It has to be generous enough that a
	# NAT full of users signing out does not start 429-ing — a throttled logout
	# leaves a live session behind, which is the failure mode worth avoiding.
	"logout": "20/min",
	"client_events": "30/min",
	"password_reset": "3/min",
	"password_reset_confirm": "5/min",
}

REST_FRAMEWORK: dict[str, Any] = {
	"DEFAULT_PERMISSION_CLASSES": [
		"rest_framework.permissions.IsAuthenticated",
	],
	"DEFAULT_AUTHENTICATION_CLASSES": [
		"accounts.authentication.SessionTokenAuthentication",
	],
	"DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
	"DEFAULT_THROTTLE_CLASSES": [
		"rest_framework.throttling.UserRateThrottle",
		"rest_framework.throttling.AnonRateThrottle",
	],
	"DEFAULT_THROTTLE_RATES": _REST_THROTTLE_RATES,
}

SPECTACULAR_SETTINGS = {
	"TITLE": "Notif API",
	"DESCRIPTION": (
		"Personal update monitoring and notification service.\n\n"
		"Monitors URLs for changes via pluggable scraping strategies "
		"(RSS/Atom feeds, CSS selectors, forum threadmarks, and more)."
	),
	"VERSION": settings.VERSION,
	"SERVE_INCLUDE_SCHEMA": False,
}

# Logs go to stdout/stderr so Docker's json-file driver and systemd's
# journald can capture them. WARNING and above additionally become
# SystemEvent rows via the system_event handler.
LOGGING: dict[str, Any] = {
	"version": 1,
	"disable_existing_loggers": False,
	"formatters": {
		"default": {
			"format": "{asctime} {levelname} {name} {message}",
			"style": "{",
		},
	},
	"handlers": {
		"console": {
			"class": "logging.StreamHandler",
			"formatter": "default",
		},
		"system_event": {
			"class": "ops.logging.SystemEventHandler",
			"formatter": "default",
			"level": "WARNING",
		},
	},
	"root": {
		"handlers": ["console", "system_event"],
		"level": "INFO",
	},
}


# ── device sessions ──────────────────────────────────────────
# Lifetimes are derived from config rather than written onto rows, so retuning
# one takes effect on the next request instead of needing a data migration.
SESSION_IDLE_LIFETIME_DAYS = settings.SESSION_IDLE_LIFETIME_DAYS
SESSION_ABSOLUTE_LIFETIME_DAYS = settings.SESSION_ABSOLUTE_LIFETIME_DAYS

SESSION_TOKEN_COOKIE_NAME = "notif_session"
# Every authenticated API call lives under this prefix, and nothing else does.
SESSION_TOKEN_COOKIE_PATH = "/api/v1/"
# Strict, not Lax: web auth is declared same-origin-only (the Caddyfile serves the
# SPA and the API from one host), so no legitimate cross-site navigation ever
# needs to carry this cookie.
SESSION_TOKEN_COOKIE_SAMESITE = "Strict"
# Unconditional, including local dev: Chromium treats loopback as a trustworthy
# origin and accepts Secure cookies over plain HTTP there. Making the flag
# conditional on DEBUG would mean the deployed configuration is one nobody ever
# runs before deploying.
SESSION_TOKEN_COOKIE_SECURE = True

# Until the cutover ages out, login and logout also expire the JWT-era refresh
# cookie. It sat at a path the new cookie's deletion does not reach, so without
# this it would linger in browsers until its own Max-Age ran out.
LEGACY_REFRESH_COOKIE_NAME = "notif_refresh"
LEGACY_REFRESH_COOKIE_PATH = "/api/v1/token/"

# Email
EMAIL_BACKEND = settings.EMAIL_BACKEND or (
	"django.core.mail.backends.smtp.EmailBackend"
	if settings.EMAIL_HOST_PASSWORD
	else "django.core.mail.backends.console.EmailBackend"
)
EMAIL_HOST = settings.EMAIL_HOST
EMAIL_PORT = settings.EMAIL_PORT
EMAIL_HOST_USER = settings.EMAIL_HOST_USER
EMAIL_HOST_PASSWORD = settings.EMAIL_HOST_PASSWORD
EMAIL_USE_TLS = settings.EMAIL_USE_TLS
EMAIL_TIMEOUT = settings.EMAIL_TIMEOUT
DEFAULT_FROM_EMAIL = settings.EMAIL_FROM
SERVER_EMAIL = settings.EMAIL_FROM
EMAIL_FROM = settings.EMAIL_FROM

RESEND_WEBHOOK_SECRET = settings.RESEND_WEBHOOK_SECRET
RESEND_AUDIENCE_ID = settings.RESEND_AUDIENCE_ID

CONFIRM_REDIRECT_URL = settings.CONFIRM_REDIRECT_URL
