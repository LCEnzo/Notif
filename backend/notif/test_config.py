"""Fail-closed environment invariants for :class:`notif.config.Settings`.

* DEBUG and the dev bootstrap login are off when nothing sets them.
* A production environment refuses to run with DEBUG on.
* The dev bootstrap login is only legal in a local DEBUG environment.
* Session lifetimes are capped at a year, so no configuration mints an
  immortal session.
* The dev bootstrap accounts are a short list the User table can hold.

The invariants are driven through environment variables, the way a container
supplies them, with ``_env_file=None`` and the relevant variables cleared so a
developer's ``.env`` or the CI environment cannot leak into the result.
"""

import json
from typing import Any

import pytest
from pydantic import ValidationError

from notif.config import DevAccount, Environment, Settings

# Env vars whose ambient values would otherwise leak into the fields under test.
_AMBIENT_KEYS = (
	"DEBUG",
	"NOTIF_ENV",
	"DEV_BOOTSTRAP_LOGIN_ENABLED",
	"DEV_BOOTSTRAP_ACCOUNTS",
	"DJANGO_SECRET_KEY",
	"SESSION_IDLE_LIFETIME_DAYS",
	"SESSION_ABSOLUTE_LIFETIME_DAYS",
)

# DJANGO_SECRET_KEY is required by the model.
_SECRET = "test-secret-key"  # pragma: allowlist secret
_ACCOUNT_PASSWORD = "dev-account-password"  # pragma: whitelist secret


@pytest.fixture(autouse=True)
def _hermetic_env(monkeypatch: pytest.MonkeyPatch) -> None:
	"""Strip config env vars so each test sees only what it sets."""
	for key in _AMBIENT_KEYS:
		monkeypatch.delenv(key, raising=False)


def test_debug_and_bootstrap_login_default_off() -> None:
	settings = Settings(_env_file=None, DJANGO_SECRET_KEY=_SECRET)

	assert settings.DEBUG is False
	assert settings.DEV_BOOTSTRAP_LOGIN_ENABLED is False


def test_session_lifetime_defaults() -> None:
	settings = Settings(_env_file=None, DJANGO_SECRET_KEY=_SECRET)

	assert (settings.SESSION_IDLE_LIFETIME_DAYS, settings.SESSION_ABSOLUTE_LIFETIME_DAYS) == (14, 365)


@pytest.mark.parametrize("key", ["SESSION_IDLE_LIFETIME_DAYS", "SESSION_ABSOLUTE_LIFETIME_DAYS"])
@pytest.mark.parametrize(("days", "accepted"), [(0, False), (1, True), (365, True), (366, False)])
def test_session_lifetimes_are_bounded(key: str, days: int, *, accepted: bool, monkeypatch: pytest.MonkeyPatch) -> None:
	monkeypatch.setenv(key, str(days))

	if accepted:
		assert getattr(Settings(_env_file=None, DJANGO_SECRET_KEY=_SECRET), key) == days
	else:
		with pytest.raises(ValidationError) as excinfo:
			Settings(_env_file=None, DJANGO_SECRET_KEY=_SECRET)
		assert [error["loc"] for error in excinfo.value.errors()] == [(key,)]


def _account(username: str, **overrides: str) -> dict[str, str]:
	return {"username": username, "password": _ACCOUNT_PASSWORD, "email": f"{username}@notif.local", **overrides}


def _settings_with_accounts(accounts: list[dict[str, str]], monkeypatch: pytest.MonkeyPatch) -> Settings:
	monkeypatch.setenv("DEV_BOOTSTRAP_ACCOUNTS", json.dumps(accounts))
	return Settings(_env_file=None, DJANGO_SECRET_KEY=_SECRET)


def _assert_accounts_rejected(accounts: list[dict[str, str]], monkeypatch: pytest.MonkeyPatch) -> None:
	with pytest.raises(ValidationError) as excinfo:
		_settings_with_accounts(accounts, monkeypatch)
	locations: list[Any] = [error["loc"] for error in excinfo.value.errors()]
	assert locations
	assert all(loc[0] == "DEV_BOOTSTRAP_ACCOUNTS" for loc in locations)


def test_dev_bootstrap_default_accounts() -> None:
	accounts = Settings(_env_file=None, DJANGO_SECRET_KEY=_SECRET).DEV_BOOTSTRAP_ACCOUNTS

	# LCEnzo is what the frontend's debug login sends; Liang is the README's example.
	assert [(account.username, account.email, account.name) for account in accounts] == [
		("LCEnzo", "lcenzo@notif.local", "LCEnzo"),
		("Liang", "liang@notif.local", "Liang"),
	]
	assert accounts[1].password == "change-me"  # pragma: whitelist secret


def test_dev_bootstrap_accounts_parse_from_json_env(monkeypatch: pytest.MonkeyPatch) -> None:
	expected = (
		DevAccount(username="ada", password=_ACCOUNT_PASSWORD, email="ada@notif.local", name="ada"),
		DevAccount(username="bob", password=_ACCOUNT_PASSWORD, email="bob@notif.local", name="Robert"),
	)

	settings = _settings_with_accounts([_account("ada"), _account("bob", name="Robert")], monkeypatch)
	accounts = settings.DEV_BOOTSTRAP_ACCOUNTS

	assert accounts == expected


@pytest.mark.parametrize(("count", "accepted"), [(0, False), (1, True), (8, True), (9, False)])
def test_dev_bootstrap_account_count_is_bounded(count: int, *, accepted: bool, monkeypatch: pytest.MonkeyPatch) -> None:
	accounts = [_account(f"dev{index}") for index in range(count)]

	if accepted:
		assert len(_settings_with_accounts(accounts, monkeypatch).DEV_BOOTSTRAP_ACCOUNTS) == count
	else:
		_assert_accounts_rejected(accounts, monkeypatch)


@pytest.mark.parametrize(
	"accounts",
	[
		pytest.param([_account("dev"), _account("dev", email="other@notif.local")], id="duplicate-username"),
		pytest.param([_account("dev"), _account("other", email="DEV@notif.local")], id="duplicate-email"),
		pytest.param([_account("", email="dev@notif.local")], id="empty-username"),
		pytest.param([_account("dev", password="")], id="empty-password"),
		pytest.param([_account("dev", email="")], id="empty-email"),
		pytest.param([_account("dev", name="")], id="empty-name"),
		pytest.param([_account("dev", nmae="Dev")], id="unknown-key"),
	],
)
def test_invalid_dev_bootstrap_accounts_are_rejected(
	accounts: list[dict[str, str]], monkeypatch: pytest.MonkeyPatch
) -> None:
	_assert_accounts_rejected(accounts, monkeypatch)


def test_dev_bootstrap_usernames_compare_case_sensitively(monkeypatch: pytest.MonkeyPatch) -> None:
	# As the User table does: these are two accounts, so config must not merge or refuse them.
	accounts = [_account("dev"), _account("Dev", email="dev2@notif.local")]

	assert len(_settings_with_accounts(accounts, monkeypatch).DEV_BOOTSTRAP_ACCOUNTS) == 2


@pytest.mark.parametrize("env", list(Environment))
@pytest.mark.parametrize("debug", [True, False])
@pytest.mark.parametrize("bootstrap", [True, False])
def test_environment_invariants(
	env: Environment, *, debug: bool, bootstrap: bool, monkeypatch: pytest.MonkeyPatch
) -> None:
	monkeypatch.setenv("NOTIF_ENV", env.value)
	monkeypatch.setenv("DEBUG", str(debug).lower())
	monkeypatch.setenv("DEV_BOOTSTRAP_LOGIN_ENABLED", str(bootstrap).lower())
	# Written from the policy, not the validator: production never claims DEBUG, and the
	# public-credential bootstrap login needs an env that is both local and DEBUG.
	legal = not (env is Environment.PRODUCTION and debug) and (not bootstrap or (debug and env is Environment.LOCAL))

	if legal:
		settings = Settings(_env_file=None, DJANGO_SECRET_KEY=_SECRET)
		resolved = (settings.NOTIF_ENV, settings.DEBUG, settings.DEV_BOOTSTRAP_LOGIN_ENABLED)
		assert resolved == (env, debug, bootstrap)
	else:
		with pytest.raises(ValidationError) as excinfo:
			Settings(_env_file=None, DJANGO_SECRET_KEY=_SECRET)
		# An invariant fired, not an unrelated field error such as a missing value.
		assert [error["type"] for error in excinfo.value.errors()] == ["value_error"]


def test_rejected_value_is_not_echoed(monkeypatch: pytest.MonkeyPatch) -> None:
	# A traceback prints str(exc). Nested, so it also covers DevAccount under Settings' flag.
	with pytest.raises(ValidationError) as excinfo:
		_settings_with_accounts([_account("dev", leftover="rejected-value-sentinel")], monkeypatch)

	assert "rejected-value-sentinel" not in str(excinfo.value)
