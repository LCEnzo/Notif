"""Typed application settings via pydantic-settings.

Instantiated once at module level — import ``settings`` from here.
Replaces scattered ``os.getenv()`` calls with a single validated config object.
"""

from enum import StrEnum

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Environment(StrEnum):
    LOCAL = "local"
    STAGING = "staging"
    PRODUCTION = "production"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    # ── environment ────────────────────────────────────────
    NOTIF_ENV: Environment = Environment.LOCAL

    # ── core ──────────────────────────────────────────────
    DEBUG: bool = True
    DJANGO_SECRET_KEY: str
    ALLOWED_HOSTS: str = "localhost,127.0.0.1,[::1]"
    SQLITE_PATH: str = "db.sqlite3"

    # ── runserver ─────────────────────────────────────────
    BACKEND_PORT: int | None = None
    RUNSERVER_HOST: str = "127.0.0.1"

    # ── dev bootstrap ─────────────────────────────────────
    DEV_BOOTSTRAP_LOGIN_ENABLED: bool | None = None
    DEV_BOOTSTRAP_USERNAME: str = "LCEnzo"
    DEV_BOOTSTRAP_PASSWORD: str = "1ukacolic"
    DEV_BOOTSTRAP_EMAIL: str = "lcenzo@notif.local"
    DEV_BOOTSTRAP_NAME: str = ""

    # ── dev latency middleware ────────────────────────────
    DEV_API_LATENCY_MS: int = 0
    DEV_API_LATENCY_JITTER_MS: int = 0

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
