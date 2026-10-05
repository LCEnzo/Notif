"""Schema-driven fuzzing: every documented operation, generated inputs, real HTTP.

Where ``test_openapi_conformance.py`` proves one hand-written round trip matches
the schema, this drives the *whole* committed ``openapi.json`` — Schemathesis
generates inputs from each operation's parameter and body schemas, calls the
live server, and checks the response.

Two profiles, selected by ``NOTIF_FUZZ_PROFILE``:

``ci`` (default)
	Small, seeded, and cheap enough to gate every push. It asserts one
	thing: no generated input produces a 5xx. That is the check with the best
	signal-to-noise ratio on an API that was not written schema-first — a 500 is
	unambiguously a bug, whereas an undocumented 400 is usually just a docs gap.

``deep``
	Every default Schemathesis check but one (status code, content type,
	headers, response schema conformance, auth enforcement, …) across the
	``examples``, ``coverage`` and ``fuzzing`` phases at a much higher example
	count. Expected to find things, which is why it is opt-in and never gates a
	merge. Run it from ``.github/workflows/deep-sweeps.yml``'s schedule or by
	hand:

		NOTIF_FUZZ_PROFILE=deep uv run pytest -q test_api_fuzz.py

Excluded operations are listed in ``UNFUZZABLE_OPERATIONS`` with the reason for
each: fuzzing them would break the fuzzer itself, reach outside the test
process, or cost far more than it finds, or they fail on a known server error
that is excluded until it is fixed.
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
from hypothesis import HealthCheck
from hypothesis import settings as hypothesis_settings
from hypothesis import strategies as st
from schemathesis import Case, CheckFunction
from schemathesis.checks import CHECKS as CHECKS_REGISTRY
from schemathesis.checks import load_all_checks, not_a_server_error

# Checks register lazily; EXCLUDED_CHECKS below resolves one of them by name.
load_all_checks()

BACKEND_ROOT = Path(__file__).resolve().parent

# `format: uri` is the single most expensive thing in this schema to generate.
# hypothesis-jsonschema satisfies it by generating strings and filtering, and
# almost everything it generates fails the filter — one operation spent 78s to
# find five examples. Building URLs directly instead makes generation ~free and
# produces better inputs than the filter ever did: the host list deliberately
# mixes public names with loopback, link-local and private addresses so the
# link validator's rejection path is exercised, not just its happy path. That
# check reads the URL alone (``safe_fetch.reject_non_public_literal``), so it
# runs for real here even though conftest stubs out DNS resolution.
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

# Operations that cannot be fuzzed, and why. Anything not listed here is fair
# game; keep this set small and keep the justifications concrete, because every
# entry is API surface that nothing is fuzzing.
UNFUZZABLE_OPERATIONS = {
	# Destroy the very session the fuzzer authenticates with, so every
	# subsequent generated call in the same test would 401 for the wrong reason.
	"auth_logout_create": "revokes the fuzzer's own session",
	"auth_sessions_revoke_all_create": "revokes the fuzzer's own session",
	# Hypothesis favours small integers, and one of them is the fuzzer's own id.
	"accounts_users_destroy": "can delete the fuzzer's own user; also 500s on a non-integer id",
	# Known server errors, excluded so the ci gate keeps measuring new ones.
	# Re-include each once it is fixed. (Neither can rotate the fuzzer's
	# password: change_password needs the current one, and update refuses it.)
	"accounts_users_update": "500s on a non-integer id: int() in IsRequestingThemselves",
	"accounts_users_partial_update": "500s on a non-integer id: int() in IsRequestingThemselves",
	"accounts_users_change_password_create": "500s on a non-object JSON body: assert in the view",  # pragma: allowlist secret
	# Reach outside the test process.
	"monitoring_trigger_scrape_create": "performs real outbound HTTP to scrape targets",
	"accounts_password_reset_create": "sends mail and consumes the reset budget",  # pragma: allowlist secret
	# Streams the entire SQLite database on every generated example; correctness
	# is covered by ops/tests.py, and the bytes are pure cost here.
	"ops_backup_sqlite_retrieve": "streams the whole database per example",
}

_PROFILE = os.environ.get("NOTIF_FUZZ_PROFILE", "ci").strip().lower()
if _PROFILE not in {"ci", "deep"}:
	raise ValueError(f"NOTIF_FUZZ_PROFILE must be 'ci' or 'deep', got {_PROFILE!r}")

_IS_DEEP = _PROFILE == "deep"

# Bounded on both axes: examples per operation, and the pytest-timeout ceiling
# that overrides addopts' global 30s (which a fuzz run legitimately exceeds).
MAX_EXAMPLES = int(os.environ.get("NOTIF_FUZZ_MAX_EXAMPLES", "200" if _IS_DEEP else "5"))
TIMEOUT_SECONDS = 1800 if _IS_DEEP else 120

# ``ci`` narrows to the one check that cannot produce a false positive; ``deep``
# passes None, which means "all of Schemathesis' default checks".
CHECKS: list[CheckFunction] | None = None if _IS_DEEP else [cast("CheckFunction", not_a_server_error)]

# ``negative_data_rejection`` demands a 4xx for every schema-violating request,
# and DRF is lenient by design: it ignores unknown query parameters and coerces
# scalars (``"name": 0`` saves as ``"0"``). Run against this API it reports that
# leniency on most write and list operations, burying the findings that matter.
# cast: the registry is typed to also hand back check *classes*, but this one is
# registered as a plain function and that is what call_and_validate accepts.
EXCLUDED_CHECKS = cast("list[CheckFunction]", list(CHECKS_REGISTRY.get_by_names(["negative_data_rejection"])))

# Phase selection is what actually decides the runtime, far more than
# ``max_examples``. Measured on POST /api/v1/monitoring/links/: the ``fuzzing``
# phase costs ~1s, the ``coverage`` phase ~32s, and ``coverage`` is insensitive
# to ``max_examples`` because it deterministically enumerates schema edge cases
# (missing required fields, wrong types, boundary values) rather than sampling.
# So CI takes the cheap sampled phase and the deep profile buys the thorough
# systematic one. Dropping ``coverage`` from CI is the difference between a 20s
# job and a 3-minute one.
# ``stateful`` is deliberately absent: ``schema.parametrize()`` never runs it (it
# needs ``schema.as_state_machine()``), so listing it would only claim coverage.
PHASES = ["examples", "coverage", "fuzzing"] if _IS_DEEP else ["fuzzing"]

schema = schemathesis.openapi.from_path(BACKEND_ROOT / "openapi.json").exclude(operation_id=list(UNFUZZABLE_OPERATIONS))
schema.config.phases.update(phases=PHASES)
# ``ci`` is a merge gate, so it replays the same inputs on every run: a red gate
# then means the diff under review changed the outcome, never that this run
# happened to sample a new input. Exploration is ``deep``'s job, which keeps a
# fresh seed per run. The inputs still move when an operation's schema or the
# Hypothesis/Schemathesis versions change — each of those is part of the diff
# that turned the gate red. Schemathesis seeds every test itself (a random seed
# unless told otherwise), and that seed outranks Hypothesis' ``derandomize``.
# One residual source remains: for a few operations the generated inputs also
# depend on Python's per-process hash seed, so exact replay additionally needs
# PYTHONHASHSEED pinned in the environment that runs pytest.
if not _IS_DEEP:
	schema.config.seed = 0
# By default Schemathesis treats the schema's security schemes as parameters and
# generates a value for each: a random ``notif_session`` cookie and a random
# ``Authorization`` header. The random cookie went out alongside the real one,
# Django kept the last of the two, and every secured operation answered 401 — the
# fuzzer never got past authentication. The real credential is now passed per
# call (see ``FuzzCredentials``), which would override the random cookie, but a
# random header that happened to start with ``Session `` would still be a 401.
# Random credentials only exercise the auth layer's first branch anyway, so turn
# them off rather than carry the noise.
schema.config.generation.update(with_security_parameters=False)

FUZZ_USERNAME = "fuzzer"
FUZZ_PASSWORD = "fuzzer-pass-123"  # pragma: allowlist secret
FUZZ_EMAIL = "fuzzer@example.com"


@dataclass(frozen=True, slots=True)
class FuzzCredentials:
	"""The fuzzer's cookie-transport session, handed to Schemathesis per call.

	Passed as ``cookies``/``headers`` arguments rather than through a
	``requests.Session`` cookie jar: Schemathesis treats a credential it was
	handed explicitly as the real one, and strips exactly that when a check
	(``ignored_auth``) needs to replay a request unauthenticated.
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
	"""Resolve ``localhost`` to 127.0.0.1 alone. Purely a speed fix.

	The live server binds 127.0.0.1 and the fuzzer opens a fresh connection per
	request. On Windows every such connect tries ::1 first and stalls ~2s on the
	refusal, which takes this module from ~15s to ~105s.
	"""
	real_getaddrinfo = socket.getaddrinfo

	def getaddrinfo(host: bytes | str | None, port: bytes | str | int | None, *args: Any, **kwargs: Any) -> Any:
		return real_getaddrinfo("127.0.0.1" if host == "localhost" else host, port, *args, **kwargs)

	monkeypatch.setattr(socket, "getaddrinfo", getaddrinfo)


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
	# live_server is session-scoped, but the transactional database and the
	# login session are per-test: Hypothesis cannot reset them between examples,
	# so state accumulates within one operation's run. That is acceptable here —
	# each example is an independent request and the database is truncated
	# between operations — but it has to be declared or Hypothesis refuses.
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
	# The ci profile fails only on a 5xx, so a fuzzer stuck at the auth layer
	# would pass green while exercising nothing behind it. A valid credential
	# never earns a 401 on a secured operation; one here means it did not land.
	assert not (response.status_code == 401 and _requires_auth(case)), (
		f"fuzzer credential was rejected; generated requests are not reaching the handler: {response.text}"
	)
	# The same blind spot one layer down: cookie-transport writes enforce CSRF,
	# and a token pair that does not land turns every unsafe method into a 403.
	assert not (response.status_code == 403 and "CSRF Failed" in response.text), (
		f"fuzzer CSRF token was rejected; generated writes are not reaching the handler: {response.text}"
	)
