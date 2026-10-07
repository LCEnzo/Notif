"""Schema-driven fuzzing of the documented API: generated inputs, real HTTP.

Profiles (``NOTIF_FUZZ_PROFILE``), how to run them, and why the settings below are what they are: docs/testing.md.
"""

import os
import socket
from collections.abc import Callable
from pathlib import Path
from typing import Any, NoReturn, cast

import pytest
import schemathesis
from django.conf import settings
from django.db import connections
from django.db.backends.sqlite3.base import DatabaseWrapper as SQLiteDatabaseWrapper
from django.middleware.csrf import CSRF_ALLOWED_CHARS, CSRF_SECRET_LENGTH
from django.utils.crypto import get_random_string
from hypothesis import HealthCheck
from hypothesis import settings as hypothesis_settings
from hypothesis import strategies as st
from schemathesis import AuthContext, Case, CheckFunction
from schemathesis.checks import CHECKS as CHECKS_REGISTRY
from schemathesis.checks import load_all_checks, not_a_server_error

from accounts import device_sessions
from accounts.models import DeviceSession

# Checks register lazily; EXCLUDED_CHECKS below resolves one of them by name.
load_all_checks()

BACKEND_ROOT = Path(__file__).resolve().parent

# Strings for `format: uri`, mixing public and non-public hosts: see docs/testing.md.
_FUZZ_URI = st.builds(
	"{}://{}{}{}".format,
	st.sampled_from(["http", "https"]),
	st.sampled_from(
		[
			"example.com",
			"sub.example.org",
			"example.net:8443",
			"127.0.0.1",
			"localhost",
			"[::1]",
			"192.168.1.1",
			"169.254.169.254",
			"10.0.0.1",
		]
	),
	st.text(alphabet=st.characters(min_codepoint=33, max_codepoint=126, blacklist_characters="#?"), max_size=40).map(
		lambda path: f"/{path}"
	),
	st.one_of(
		st.just(""),
		st.text(alphabet=st.characters(min_codepoint=33, max_codepoint=126, blacklist_characters="#"), max_size=30).map(
			lambda query: f"?{query}"
		),
	),
)
schemathesis.openapi.format("uri", _FUZZ_URI)

# Every entry is API surface nothing fuzzes: keep the set small. Reasons: docs/testing.md.
UNFUZZABLE_OPERATIONS = {
	"auth_logout_create": "revokes the fuzzer's own session",
	"accounts_users_destroy": "can delete the fuzzer's own user",
}

_PROFILE = os.environ.get("NOTIF_FUZZ_PROFILE", "ci").strip().lower()
if _PROFILE not in {"ci", "deep"}:
	raise ValueError(f"NOTIF_FUZZ_PROFILE must be 'ci' or 'deep', got {_PROFILE!r}")

_IS_DEEP = _PROFILE == "deep"

# The per-test timeout replaces addopts' 30s: see docs/testing.md.
MAX_EXAMPLES = int(os.environ.get("NOTIF_FUZZ_MAX_EXAMPLES", "200" if _IS_DEEP else "5"))
TIMEOUT_SECONDS = 1800 if _IS_DEEP else 120

# ``ci`` keeps only ``not_a_server_error``, whose failures are always real bugs;
# ``deep`` passes None, which selects Schemathesis' default checks.
CHECKS: list[CheckFunction] | None = None if _IS_DEEP else [cast("CheckFunction", not_a_server_error)]

# ``negative_data_rejection`` reports DRF's deliberate leniency as failures: see docs/testing.md.
# cast: the registry is typed to also hand back check *classes*, but this one is
# registered as a plain function and that is what validate_response accepts.
EXCLUDED_CHECKS = cast("list[CheckFunction]", list(CHECKS_REGISTRY.get_by_names(["negative_data_rejection"])))

# ``ci`` samples, ``deep`` enumerates; ``schema.parametrize()`` never runs ``stateful``. See docs/testing.md.
PHASES = ["examples", "coverage", "fuzzing"] if _IS_DEEP else ["fuzzing"]

schema = schemathesis.openapi.from_path(BACKEND_ROOT / "openapi.json").exclude(operation_id=list(UNFUZZABLE_OPERATIONS))
schema.config.phases.update(phases=PHASES)
# ``ci`` replays the same inputs every run; exact only with PYTHONHASHSEED pinned. See docs/testing.md.
if not _IS_DEEP:
	schema.config.seed = 0
# No generated credentials: a random ``Authorization`` header outranks the real cookie. See docs/testing.md.
schema.config.generation.update(with_security_parameters=False)

FUZZ_USERNAME = "fuzzer"
FUZZ_PASSWORD = "fuzzer-pass-123"  # pragma: allowlist secret
FUZZ_EMAIL = "fuzzer@example.com"
# Fixed per process, because Schemathesis also applies the auth provider at collection: see docs/testing.md.
FUZZ_SESSION_TOKEN = device_sessions.generate_token()
FUZZ_CSRF_TOKEN = get_random_string(CSRF_SECRET_LENGTH, allowed_chars=CSRF_ALLOWED_CHARS)


@schema.auth(refresh_interval=None)
class FuzzSession:
	"""Signs every generated request in as the fuzz user over cookie transport, with a matching CSRF pair."""

	def get(self, case: Case[Any], context: AuthContext) -> str:
		return FUZZ_SESSION_TOKEN

	def set(self, case: Case[Any], data: str, context: AuthContext) -> None:
		case.cookies.update({settings.SESSION_TOKEN_COOKIE_NAME: data, settings.CSRF_COOKIE_NAME: FUZZ_CSRF_TOKEN})
		case.headers["X-CSRFToken"] = FUZZ_CSRF_TOKEN


@pytest.fixture
def fuzz_user(django_user_model: Any) -> Any:
	"""Create the fuzz user and the session that ``FUZZ_SESSION_TOKEN`` names, inside the test's own database state.

	The session comes from the login view's ``create_session``, with only its token pinned.
	"""
	user = django_user_model.objects.create_user(username=FUZZ_USERNAME, password=FUZZ_PASSWORD, email=FUZZ_EMAIL)
	with pytest.MonkeyPatch.context() as patch:
		patch.setattr(device_sessions, "generate_token", lambda: FUZZ_SESSION_TOKEN)
		issued = device_sessions.create_session(
			user=user,
			transport=DeviceSession.Transport.COOKIE,
			device_label="fuzzer",
			ip=None,
			user_agent="",
			password_hash_at_login=user.password,
		)
	assert issued.token == FUZZ_SESSION_TOKEN
	return user


@pytest.fixture
def ipv4_localhost(monkeypatch: pytest.MonkeyPatch) -> None:
	"""Resolve ``localhost`` to 127.0.0.1 alone. Purely a speed fix, for Windows: see docs/testing.md."""
	real_getaddrinfo = socket.getaddrinfo

	def getaddrinfo(host: bytes | str | None, port: bytes | str | int | None, *args: Any, **kwargs: Any) -> Any:
		return real_getaddrinfo("127.0.0.1" if host == "localhost" else host, port, *args, **kwargs)

	monkeypatch.setattr(socket, "getaddrinfo", getaddrinfo)


def test_live_server_shares_the_test_database_connection(live_server: Any) -> None:
	"""The live server serves requests over the test's own in-memory connection (see conftest.live_server)."""
	default = connections["default"]
	assert isinstance(default, SQLiteDatabaseWrapper)
	assert default.is_in_memory_db()
	assert live_server.thread.connections_override.get("default") is default


@pytest.mark.django_db(transaction=True)
@pytest.mark.usefixtures("ipv4_localhost", "fuzz_user")
def test_the_fuzz_session_passes_auth_and_csrf(live_server: Any) -> None:
	"""Positive control for both canaries: the provider's credential gets a read and a write through."""
	for method, path in [
		("GET", "/api/v1/accounts/users/get_my_info/"),
		("POST", "/api/v1/monitoring/notifications/mark_all_read/"),
	]:
		case = schema[path][method].Case()
		schema.auth.set(case, AuthContext(operation=case.operation, app=schema.app))
		response = case.call(base_url=live_server.url)
		assert response.status_code == 200, f"{method} {path}: {response.text}"


def _requires_auth(case: Case[Any]) -> bool:
	"""True when the operation declares no anonymous (``{}``) security alternative.

	The schema declares security per operation and has no global default, so the
	operation's own list is the whole answer.
	"""
	security = case.operation.definition.raw.get("security") or []
	return {} not in security


@schema.parametrize()
@hypothesis_settings(
	max_examples=MAX_EXAMPLES,
	deadline=None,
	# Per-test state accumulates across one operation's examples: see docs/testing.md.
	suppress_health_check=[HealthCheck.function_scoped_fixture, HealthCheck.too_slow],
)
@pytest.mark.timeout(TIMEOUT_SECONDS)
@pytest.mark.django_db(transaction=True)
@pytest.mark.fuzz
@pytest.mark.usefixtures("ipv4_localhost", "fuzz_user")
def test_operation_survives_generated_input(
	case: Case[Any],
	live_server: Any,
	fuzz_canary: Callable[[str, str], NoReturn],
) -> None:
	# transaction=True is required: live_server serves from a separate thread and
	# connection, so the fuzzing user must be committed for its session to be seen.
	# call_and_validate in two halves, so the canaries go first: see docs/testing.md.
	response = case.call(base_url=live_server.url)
	# ci fails only on a 5xx, so catch a fuzzer stuck at the auth layer: see docs/testing.md.
	if response.status_code == 401 and _requires_auth(case):
		fuzz_canary(
			"credential",
			f"fuzzer credential was rejected; generated requests are not reaching the handler: {response.text}",
		)
	# The same blind spot one layer down: cookie-transport writes enforce CSRF,
	# and a token pair that does not land turns every unsafe method into a 403.
	if response.status_code == 403 and "CSRF Failed" in response.text:
		fuzz_canary(
			"csrf",
			f"fuzzer CSRF token was rejected; generated writes are not reaching the handler: {response.text}",
		)
	case.validate_response(
		response,
		checks=CHECKS,
		excluded_checks=EXCLUDED_CHECKS,
		transport_kwargs={"base_url": live_server.url},
	)


def test_the_auth_provider_asks_for_no_reauth_replay() -> None:
	"""The split above skips call_and_validate's reauth replay, a no-op only while no provider asks for one."""
	assert schema.reauth_retry_statuses == frozenset()
