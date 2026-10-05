"""Contracts between the per-environment settings modules.

Modules are re-executed with ``runpy`` against a patched ``notif.config``
instead of being read off ``django.conf.settings``: the live values were fixed
at import time from whatever the developer's ``.env`` or the CI environment
happened to say, so asserting on them could pass without exercising anything.
"""

import runpy

import pytest

from notif import config


@pytest.mark.parametrize("module", ["notif.settings_base", "notif.settings_prod"])
def test_bootstrap_login_stays_off_whatever_the_env_attests(module: str, monkeypatch: pytest.MonkeyPatch) -> None:
	# The worst case config can validate: an env claiming to be a local debug box.
	monkeypatch.setattr(config.settings, "DEV_BOOTSTRAP_LOGIN_ENABLED", True)

	assert runpy.run_module(module)["DEV_BOOTSTRAP_LOGIN_ENABLED"] is False
