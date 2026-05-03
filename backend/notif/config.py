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
	DEBUG: bool = True
	DJANGO_SECRET_KEY: str = Field(min_length=1)
	ALLOWED_HOSTS: str = Field(default="localhost,127.0.0.1,[::1]", min_length=1)
	CORS_ALLOWED_ORIGINS: str = Field(default="", description="Comma-separated origins, e.g. https://notif.example.com")
	CSRF_TRUSTED_ORIGINS: str = Field(
		default="",
		description="Comma-separated scheme+host origins that POSTs are accepted from, e.g. https://notif.example.com. Required behind an HTTPS reverse proxy.",
	)
	SQLITE_PATH: str = Field(default="db.sqlite3", min_length=1)

	# ── static files ───────────────────────────────────────
	STATIC_ROOT: str = Field(default="staticfiles", min_length=1)

	# ── runserver ─────────────────────────────────────────
	BACKEND_PORT: int | None = Field(default=None, ge=1, le=65_535)
	RUNSERVER_HOST: str = Field(default="127.0.0.1", min_length=1)

	# ── dev bootstrap ─────────────────────────────────────
	DEV_BOOTSTRAP_LOGIN_ENABLED: bool | None = None
	DEV_BOOTSTRAP_USERNAME: str = Field(default="LCEnzo", min_length=1)
	DEV_BOOTSTRAP_PASSWORD: str = Field(default="1ukacolic", min_length=1)
	DEV_BOOTSTRAP_EMAIL: str = Field(default="lcenzo@notif.local", min_length=1)
	DEV_BOOTSTRAP_NAME: str = ""

	# ── dev latency middleware ────────────────────────────
	DEV_API_LATENCY_MS: int = Field(default=0, ge=0, le=_MAX_DEV_API_LATENCY_MS)
	DEV_API_LATENCY_JITTER_MS: int = Field(default=0, ge=0, le=_MAX_DEV_API_LATENCY_MS)

	# ── build info (exposed via status endpoint) ──────────
	VERSION: str = "0.2.0"
	GIT_HASH: str = "dev"

	@model_validator(mode="after")
	def _resolve_conditional_defaults(self) -> Settings:
		"""Defaults that depend on other fields.

		* DEV_BOOTSTRAP_LOGIN_ENABLED defaults to ``DEBUG`` when not set.
		* DEV_BOOTSTRAP_NAME defaults to DEV_BOOTSTRAP_USERNAME when empty.
		"""
		if self.DEV_BOOTSTRAP_LOGIN_ENABLED is None:
			self.DEV_BOOTSTRAP_LOGIN_ENABLED = self.DEBUG
		if not self.DEV_BOOTSTRAP_NAME:
			self.DEV_BOOTSTRAP_NAME = self.DEV_BOOTSTRAP_USERNAME
		return self

	@property
	def is_local(self) -> bool:
		return self.NOTIF_ENV == Environment.LOCAL


settings = Settings()
