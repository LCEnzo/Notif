"""Schema-driven fuzzing of the documented API: generated inputs, real HTTP.

Profiles (``NOTIF_FUZZ_PROFILE``), how to run them, and why the settings below are what they are: docs/testing.md.
"""

import os
import socket
from dataclasses import dataclass
from pathlib import Path
from typing import Any, cast

import pytest
import requests
import schemathesis
from django.conf import settings
from django.db import connections
from django.db.backends.sqlite3.base import DatabaseWrapper as SQLiteDatabaseWrapper
from hypothesis import HealthCheck
from hypothesis import settings as hypothesis_settings
from hypothesis import strategies as st
from schemathesis import Case, CheckFunction
from schemathesis.checks import CHECKS as CHECKS_REGISTRY
from schemathesis.checks import load_all_checks, not_a_server_error

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
# registered as a plain function and that is what call_and_validate accepts.
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


@dataclass(frozen=True, slots=True)
class FuzzCredentials:
	"""The fuzzer's cookie-transport session, handed to Schemathesis per call.

	Passed as ``cookies``/``headers`` arguments, not a ``requests.Session`` jar: see docs/testing.md.
	"""

	session_token: str
	csrf_token: str

	# Cookie-transport writes enforce CSRF: the csrftoken cookie and the
	# X-CSRFToken header must both be present and agree.
	def cookies(self) -> dict[str, str]:
		return {settings.SESSION_TOKEN_COOKIE_NAME: self.session_token, "csrftoken": self.csrf_token}

	def headers(self) -> dict[str, str]:
		return {"X-CSRFToken": self.csrf_token}


@pytest.fixture
def fuzz_credentials(live_server: Any, django_user_model: Any) -> FuzzCredentials:
	"""Create the fuzzing user and log it in over cookie transport.

	Function-scoped, so it costs one user creation and one login per *operation*
	rather than per generated example.
	"""
	django_user_model.objects.create_user(
		username=FUZZ_USERNAME,
		password=FUZZ_PASSWORD,
		email=FUZZ_EMAIL,
	)
	login = requests.post(
		f"{live_server.url}/api/v1/auth/login/",
		json={"username": FUZZ_USERNAME, "password": FUZZ_PASSWORD, "transport": "cookie"},
		timeout=10,
	)
	assert login.status_code == 200, login.text
	return FuzzCredentials(
		session_token=login.cookies[settings.SESSION_TOKEN_COOKIE_NAME],
		csrf_token=login.cookies["csrftoken"],
	)


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
@pytest.mark.usefixtures("ipv4_localhost")
def test_operation_survives_generated_input(
	case: Case[Any],
	live_server: Any,
	fuzz_credentials: FuzzCredentials,
) -> None:
	# transaction=True is required: live_server serves from a separate thread and
	# connection, so the fuzzing user must be committed for its login to be seen.
	response = case.call_and_validate(
		base_url=live_server.url,
		headers=fuzz_credentials.headers(),
		cookies=fuzz_credentials.cookies(),
		checks=CHECKS,
		excluded_checks=EXCLUDED_CHECKS,
	)
	# ci fails only on a 5xx, so catch a fuzzer stuck at the auth layer: see docs/testing.md.
	assert not (response.status_code == 401 and _requires_auth(case)), (
		f"fuzzer credential was rejected; generated requests are not reaching the handler: {response.text}"
	)
	# The same blind spot one layer down: cookie-transport writes enforce CSRF,
	# and a token pair that does not land turns every unsafe method into a 403.
	assert not (response.status_code == 403 and "CSRF Failed" in response.text), (
		f"fuzzer CSRF token was rejected; generated writes are not reaching the handler: {response.text}"
	)
