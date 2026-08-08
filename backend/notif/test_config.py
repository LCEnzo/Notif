"""Fail-closed environment invariants for :class:`notif.config.Settings`.

These assert the security posture of the config layer directly, by constructing
``Settings`` with explicit kwargs rather than through the process environment:

* DEBUG fails closed (defaults to False) when nothing sets it.
* A production environment refuses to run with DEBUG on.
* The dev bootstrap login is only legal in a local DEBUG environment.

Each construction is made hermetic (``_env_file=None`` plus a cleared subset of
the process environment) so the assertions reflect only the kwargs under test,
not whatever a developer — or the CI gate, which exports ``DEBUG=true`` — has
configured ambiently.
"""

import pytest
from pydantic import ValidationError

from notif.config import Environment, Settings

# Env vars whose ambient values would otherwise leak past our kwargs into the
# fields under test. Cleared per-test so an unset kwarg means "use the default".
_AMBIENT_KEYS = (
	"DEBUG",
	"NOTIF_ENV",
	"DEV_BOOTSTRAP_LOGIN_ENABLED",
	"DJANGO_SECRET_KEY",
)

# ``_env_file=None`` ignores the repo ``.env`` so results do not depend on a
# developer's local configuration; DJANGO_SECRET_KEY is required by the model.
_SECRET = "test-secret-key"  # pragma: allowlist secret


@pytest.fixture(autouse=True)
def _hermetic_env(monkeypatch: pytest.MonkeyPatch) -> None:
	"""Strip config env vars so ``Settings(...)`` reflects only its kwargs."""
	for key in _AMBIENT_KEYS:
		monkeypatch.delenv(key, raising=False)


def test_debug_defaults_false_when_unset() -> None:
	settings = Settings(_env_file=None, DJANGO_SECRET_KEY=_SECRET, NOTIF_ENV=Environment.LOCAL)
	assert settings.DEBUG is False


def test_production_with_debug_is_rejected() -> None:
	with pytest.raises((ValidationError, ValueError)):
		Settings(_env_file=None, DJANGO_SECRET_KEY=_SECRET, NOTIF_ENV=Environment.PRODUCTION, DEBUG=True)


def test_dev_bootstrap_requires_debug() -> None:
	with pytest.raises((ValidationError, ValueError)):
		Settings(
			_env_file=None,
			DJANGO_SECRET_KEY=_SECRET,
			NOTIF_ENV=Environment.LOCAL,
			DEBUG=False,
			DEV_BOOTSTRAP_LOGIN_ENABLED=True,
		)


def test_dev_bootstrap_requires_local_env() -> None:
	with pytest.raises((ValidationError, ValueError)):
		Settings(
			_env_file=None,
			DJANGO_SECRET_KEY=_SECRET,
			NOTIF_ENV=Environment.STAGING,
			DEBUG=True,
			DEV_BOOTSTRAP_LOGIN_ENABLED=True,
		)
