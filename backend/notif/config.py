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
	HEALTH_SQLITE_PATH: str | None = Field(
		default=None,
		min_length=1,
		description="Health Connect store. Defaults to health.sqlite3 beside SQLITE_PATH, so it shares its volume.",
	)
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
		"""Defaults that depend on other fields, plus fail-closed environment invariants.

		* DEV_BOOTSTRAP_NAME defaults to DEV_BOOTSTRAP_USERNAME when empty.
		* Empty email secrets are coerced to None.
		* RESEND_API_KEY is accepted as a backward-compatible alias for
			EMAIL_HOST_PASSWORD because Resend SMTP uses the API key as the
			SMTP password.
		* Fail-closed invariants: production never claims DEBUG, and the dev
			bootstrap login is only legal in a local DEBUG environment.
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

		# One file for both aliases would share django_migrations: migrating either
		# alias would mark the other's migrations applied without creating its tables.
		if Path(self.health_sqlite_path).resolve() == Path(self.SQLITE_PATH).resolve():
			raise ValueError(
				f"HEALTH_SQLITE_PATH and SQLITE_PATH both point at {self.SQLITE_PATH}; "
				"the Health Connect store needs its own file."
			)

		if self.NOTIF_ENV == Environment.PRODUCTION and self.DEBUG:
			raise ValueError(
				"NOTIF_ENV=production with DEBUG=true is not allowed: DEBUG marks a local "
				"development environment. Set DEBUG=false (the default)."
			)
		if self.DEV_BOOTSTRAP_LOGIN_ENABLED and not (self.DEBUG and self.NOTIF_ENV == Environment.LOCAL):
			raise ValueError(
				"DEV_BOOTSTRAP_LOGIN_ENABLED=true needs NOTIF_ENV=local and DEBUG=true "
				f"(got NOTIF_ENV={self.NOTIF_ENV}, DEBUG={self.DEBUG}): the bootstrap login "
				"accepts repository-public credentials. Outside local development, remove "
				"it or set it to false."
			)
		return self

	@property
	def health_sqlite_path(self) -> str:
		return self.HEALTH_SQLITE_PATH or str(Path(self.SQLITE_PATH).with_name("health.sqlite3"))

	@property
	def is_local(self) -> bool:
		return self.NOTIF_ENV == Environment.LOCAL


settings = Settings()
