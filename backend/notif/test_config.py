"""Fail-closed environment invariants for :class:`notif.config.Settings`.

* DEBUG and the dev bootstrap login are off when nothing sets them.
* A production environment refuses to run with DEBUG on.
* The dev bootstrap login is only legal in a local DEBUG environment.

The invariants are driven through environment variables, the way a container
supplies them, with ``_env_file=None`` and the relevant variables cleared so a
developer's ``.env`` or the CI environment cannot leak into the result.
"""

import pytest
from pydantic import ValidationError

from notif.config import Environment, Settings

# Env vars whose ambient values would otherwise leak into the fields under test.
_AMBIENT_KEYS = (
	"DEBUG",
	"NOTIF_ENV",
	"DEV_BOOTSTRAP_LOGIN_ENABLED",
	"DJANGO_SECRET_KEY",
)

# DJANGO_SECRET_KEY is required by the model.
_SECRET = "test-secret-key"  # pragma: allowlist secret


@pytest.fixture(autouse=True)
def _hermetic_env(monkeypatch: pytest.MonkeyPatch) -> None:
	"""Strip config env vars so each test sees only what it sets."""
	for key in _AMBIENT_KEYS:
		monkeypatch.delenv(key, raising=False)


def test_debug_and_bootstrap_login_default_off() -> None:
	settings = Settings(_env_file=None, DJANGO_SECRET_KEY=_SECRET)

	assert settings.DEBUG is False
	assert settings.DEV_BOOTSTRAP_LOGIN_ENABLED is False


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
