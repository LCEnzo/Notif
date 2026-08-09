"""Typed application settings via pydantic-settings.

Instantiated once at module level — import ``settings`` from here.
Replaces scattered ``os.getenv()`` calls with a single validated config object.
"""

from enum import StrEnum
from pathlib import Path

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Resolve .env relative to the backend package directory so lookups
# work regardless of the working directory (IDE runners, manage.py
# from repo root, Docker containers, etc.).
_ENV_FILE = Path(__file__).resolve().parent.parent / ".env"
_MAX_DEV_API_LATENCY_MS = 5_000


class Environment(StrEnum):
	LOCAL = "local"
	STAGING = "staging"
	PRODUCTION = "production"


class Settings(BaseSettings):
	model_config = SettingsConfigDict(env_file=str(_ENV_FILE), env_file_encoding="utf-8")

	# ── environment ────────────────────────────────────────
	NOTIF_ENV: Environment = Environment.LOCAL

	# ── core ──────────────────────────────────────────────
	DEBUG: bool = False
	DJANGO_SECRET_KEY: str = Field(min_length=1)
	ALLOWED_HOSTS: str = Field(default="localhost,127.0.0.1,[::1]", min_length=1)
	CORS_ALLOWED_ORIGINS: str = Field(default="", description="Comma-separated origins, e.g. https://notif.lcenzo.com")
	CSRF_TRUSTED_ORIGINS: str = Field(
		default="",
		description="Comma-separated scheme+host origins that POSTs are accepted from, e.g. https://notif.lcenzo.com. Required behind an HTTPS reverse proxy.",
	)
	DJANGO_ADMIN_URL: str = Field(
		default="admin/",
		min_length=1,
		description="URL prefix for the Django admin (must end with '/'). Override in production to reduce brute-force log noise.",
	)
	SQLITE_PATH: str = Field(default="db.sqlite3", min_length=1)
	CADDY_ACCESS_LOG_PATH: str = Field(default="/app/caddy-logs/access.json", min_length=1)

	# ── device sessions ────────────────────────────────────
	# Deliberately absent from the .env files: the defaults are the intended
	# values, and tuning a lifetime is a deploy-time knob rather than a code
	# change. Both are bounded so a typo cannot mint an immortal session.
	SESSION_IDLE_LIFETIME_DAYS: int = Field(
		default=14,
		ge=1,
		le=365,
		description="A session dies this long after its last use.",
	)
	SESSION_ABSOLUTE_LIFETIME_DAYS: int = Field(
		default=90,
		ge=1,
		le=365,
		description="A session dies this long after it was created, however actively it is used.",
	)
	# Flutter's web dev server and Django run on different ports, and Django's
	# CSRF origin comparison is port-exact — so dev must pin the Flutter port
	# (`flutter run -d chrome --web-port=<this>`) and trust exactly that origin.
	# Ignored when DEBUG is false.
	DEV_WEB_PORT: int = Field(default=5353, ge=1, le=65_535)

	# ── static files ───────────────────────────────────────
	STATIC_ROOT: str = Field(default="staticfiles", min_length=1)

	# ── runserver ─────────────────────────────────────────
	BACKEND_PORT: int | None = Field(default=None, ge=1, le=65_535)
	RUNSERVER_HOST: str = Field(default="127.0.0.1", min_length=1)

	# ── email ─────────────────────────────────────────────
	EMAIL_BACKEND: str | None = Field(default=None)
	EMAIL_FROM: str = Field(default="Notif <notif@notif.lcenzo.com>", min_length=1)
	EMAIL_HOST: str = Field(default="smtp.resend.com", min_length=1)
	EMAIL_PORT: int = Field(default=587, ge=1, le=65_535)
	EMAIL_HOST_USER: str = Field(default="resend", min_length=1)
	EMAIL_HOST_PASSWORD: str | None = Field(default=None)
	EMAIL_USE_TLS: bool = True
	EMAIL_TIMEOUT: int = Field(default=10, ge=1, le=60)
	RESEND_API_KEY: str | None = Field(default=None)
	RESEND_WEBHOOK_SECRET: str | None = Field(default=None)
	RESEND_AUDIENCE_ID: str | None = Field(default=None)
	CONFIRM_REDIRECT_URL: str = Field(default="https://notif.lcenzo.com")

	# ── dev bootstrap ─────────────────────────────────────
	DEV_BOOTSTRAP_LOGIN_ENABLED: bool = False
	DEV_BOOTSTRAP_USERNAME: str = Field(default="LCEnzo", min_length=1)
	DEV_BOOTSTRAP_PASSWORD: str = Field(default="1ukacolic", min_length=1)
	DEV_BOOTSTRAP_EMAIL: str = Field(default="lcenzo@notif.local", min_length=1)
	DEV_BOOTSTRAP_NAME: str = ""

	# ── dev latency middleware ────────────────────────────
	DEV_API_LATENCY_MS: int = Field(default=0, ge=0, le=_MAX_DEV_API_LATENCY_MS)
	DEV_API_LATENCY_JITTER_MS: int = Field(default=0, ge=0, le=_MAX_DEV_API_LATENCY_MS)

	# ── build info (exposed via status endpoint) ──────────
	VERSION: str = "0.3.0"
	GIT_HASH: str = "dev"

	@model_validator(mode="after")
	def _resolve_conditional_defaults(self) -> Settings:
		"""Defaults that depend on other fields, plus environment invariants.

		* DEV_BOOTSTRAP_NAME defaults to DEV_BOOTSTRAP_USERNAME when empty.
		* Empty email secrets are coerced to None.
		* RESEND_API_KEY is accepted as a backward-compatible alias for
			EMAIL_HOST_PASSWORD because Resend SMTP uses the API key as the
			SMTP password.
		* Fail-closed invariants: production never runs with DEBUG on, and the
			dev bootstrap login is only legal in a local DEBUG environment.
		"""
		if not self.DEV_BOOTSTRAP_NAME:
			self.DEV_BOOTSTRAP_NAME = self.DEV_BOOTSTRAP_USERNAME
		if self.EMAIL_HOST_PASSWORD == "":
			self.EMAIL_HOST_PASSWORD = None
		if self.EMAIL_BACKEND == "":
			self.EMAIL_BACKEND = None
		if self.RESEND_API_KEY == "":
			self.RESEND_API_KEY = None
		if self.EMAIL_HOST_PASSWORD is None:
			self.EMAIL_HOST_PASSWORD = self.RESEND_API_KEY

		if self.NOTIF_ENV == Environment.PRODUCTION and self.DEBUG:
			raise ValueError(
				"NOTIF_ENV=production with DEBUG=true is not allowed: it would enable the "
				"dev bootstrap login, MD5 password hashing, and the silk profiler in "
				"production. Set DEBUG=false (the default) or NOTIF_ENV=staging/local."
			)
		if self.DEV_BOOTSTRAP_LOGIN_ENABLED and not self.DEBUG:
			raise ValueError(
				"DEV_BOOTSTRAP_LOGIN_ENABLED requires DEBUG=true: the bootstrap login "
				"creates an account with repository-public credentials and must never "
				"run outside an explicit local debug environment."
			)
		if self.DEV_BOOTSTRAP_LOGIN_ENABLED and self.NOTIF_ENV != Environment.LOCAL:
			raise ValueError(
				"DEV_BOOTSTRAP_LOGIN_ENABLED requires NOTIF_ENV=local: the bootstrap "
				"login is a local-development convenience, not a staging feature."
			)
		return self

	@property
	def is_local(self) -> bool:
		return self.NOTIF_ENV == Environment.LOCAL


settings = Settings()
