"""Contracts between the per-environment settings modules.

Where a test needs a module's own values it executes the module's file afresh
instead of reading ``django.conf.settings``: settings_test rewrites the shared
REST_FRAMEWORK dict in place, and the live bootstrap flag was fixed at import
by whatever ``.env`` the process loaded, so asserting on the live values could
pass without exercising anything.
"""

import runpy
import socket
import warnings
from pathlib import Path
from typing import Any
from unittest import mock

import pytest
from django.conf import Settings
from django.core.exceptions import ImproperlyConfigured
from rest_framework.permissions import AllowAny
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.test import APIRequestFactory
from rest_framework.throttling import AnonRateThrottle, ScopedRateThrottle, SimpleRateThrottle, UserRateThrottle
from rest_framework.views import APIView

from notif import config


def _execute(settings_module: str) -> dict[str, Any]:
	# run_path, not run_module: settings_test.py matches pytest's *_test.py
	# pattern, so the assertion-rewriting import hook claims it.
	return runpy.run_path(str(Path(config.__file__).with_name(f"{settings_module}.py")))


def _production_rest_framework() -> dict[str, Any]:
	rest_framework: dict[str, Any] = _execute("settings_base")["REST_FRAMEWORK"]
	return rest_framework


class _ScopedView(APIView):
	"""Global and scoped throttles together, as the auth views run them.

	Listed explicitly rather than extending the defaults: a default
	ScopedRateThrottle would otherwise run twice and charge each request twice.
	"""

	authentication_classes: list[type[Any]] = []
	permission_classes = [AllowAny]
	throttle_classes = [UserRateThrottle, AnonRateThrottle, ScopedRateThrottle]
	throttle_scope = "login"

	def get(self, request: Request) -> Response:
		return Response(status=204)


@pytest.mark.parametrize("module", ["settings_base", "settings_prod"])
def test_bootstrap_login_stays_off_whatever_the_env_attests(module: str, monkeypatch: pytest.MonkeyPatch) -> None:
	# The worst case config can validate: an env claiming to be a local debug box.
	monkeypatch.setattr(config.settings, "DEV_BOOTSTRAP_LOGIN_ENABLED", True)

	assert _execute(module)["DEV_BOOTSTRAP_LOGIN_ENABLED"] is False


def test_test_settings_keep_production_throttle_classes() -> None:
	# APIView captured the default classes at import; they are what views run.
	running = [f"{cls.__module__}.{cls.__qualname__}" for cls in APIView.throttle_classes]

	assert running == _production_rest_framework()["DEFAULT_THROTTLE_CLASSES"]


def test_test_settings_declare_every_production_scope_without_a_rate() -> None:
	production_rates = _production_rest_framework()["DEFAULT_THROTTLE_RATES"]
	# SimpleRateThrottle captured the rates at import; they are what every throttle reads.
	running_rates = SimpleRateThrottle.THROTTLE_RATES

	# The default throttles' own scopes must be declared, or they fail on construction.
	assert {"user", "anon"} <= production_rates.keys()
	assert running_rates == dict.fromkeys(production_rates)


def test_none_rate_admits_what_a_real_rate_throttles() -> None:
	view = _ScopedView.as_view()
	factory = APIRequestFactory()

	def statuses(remote_addr: str) -> list[int]:
		return [view(factory.get("/", REMOTE_ADDR=remote_addr)).status_code for _ in range(3)]

	assert statuses("198.51.100.1") == [204, 204, 204]
	# Control: the same path does consult the throttle. Distinct documentation
	# addresses keep this history out of every other test's cache keys.
	with mock.patch.object(
		SimpleRateThrottle, "THROTTLE_RATES", {**SimpleRateThrottle.THROTTLE_RATES, "login": "1/min"}
	):
		assert statuses("198.51.100.2") == [204, 429, 429]


def test_undeclared_scope_fails_loudly() -> None:
	view = _ScopedView.as_view(throttle_scope="never-declared")

	with pytest.raises(ImproperlyConfigured, match="never-declared"):
		view(APIRequestFactory().get("/"))


def test_test_settings_refuse_a_production_environment(monkeypatch: pytest.MonkeyPatch) -> None:
	monkeypatch.setattr(config.settings, "NOTIF_ENV", config.Environment.PRODUCTION)

	with pytest.raises(RuntimeError, match="NOTIF_ENV=production"):
		_execute("settings_test")


def test_suite_cannot_connect_beyond_loopback() -> None:
	# pytest-socket (pyproject addopts) raises before a packet leaves. Without it this
	# is a real attempt on TEST-NET-1, which nothing routes: an OSError instead.
	# A socket we close ourselves, not socket.create_connection: that helper closes
	# its socket only on OSError, so pytest-socket's RuntimeError would leak it.
	with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock, pytest.raises(RuntimeError, match=r"192\.0\.2\.1"):
		sock.settimeout(1)
		sock.connect(("192.0.2.1", 9))


# settings_dev is left out: importing it extends INSTALLED_APPS, MIDDLEWARE and
# LOGGING in place, objects the running test settings share, and creates logs/.
@pytest.mark.parametrize("module", ["notif.settings_test", "notif.settings_prod"])
def test_settings_load_without_warnings(module: str) -> None:
	# Django's deprecation warnings, and its refusal of EMAIL_* settings beside
	# MAILERS, fire only when django.conf.Settings loads a module. The suite loads
	# settings_test alone, so a slip in settings_prod would otherwise first show
	# as a deploy that does not start.
	with warnings.catch_warnings(record=True) as caught:
		warnings.simplefilter("always")
		Settings(module)

	assert [f"{warning.category.__name__}: {warning.message}" for warning in caught] == []
