"""Schema-driven fuzzing: every documented operation, generated inputs, real HTTP.

Where ``test_openapi_conformance.py`` proves one hand-written round trip matches
the schema, this drives the *whole* committed ``openapi.json`` — Schemathesis
generates inputs from each operation's parameter and body schemas, calls the
live server, and checks the response.

Two profiles, selected by ``NOTIF_FUZZ_PROFILE``:

``ci`` (default)
	Small, deterministic, and cheap enough to gate every push. It asserts one
	thing: no generated input produces a 5xx. That is the check with the best
	signal-to-noise ratio on an API that was not written schema-first — a 500 is
	unambiguously a bug, whereas an undocumented 400 is usually just a docs gap.

``deep``
	Every default Schemathesis check (status code, content type, headers, and
	response schema conformance) at a much higher example count. Expected to
	find things, which is why it is opt-in and never gates a merge. Run it from
	``.github/workflows/deep-sweeps.yml``'s schedule or by hand:

		NOTIF_FUZZ_PROFILE=deep uv run pytest -q test_api_fuzz.py

Excluded operations are listed in ``UNFUZZABLE_OPERATIONS`` with the reason for
each. The exclusions are deliberately narrow: an operation is only excluded when
fuzzing it would break the fuzzer itself or reach outside the test process.
"""

import os
from collections.abc import Iterator
from pathlib import Path
from typing import Any, cast

import pytest
import requests
import schemathesis
from django.test import override_settings
from hypothesis import HealthCheck
from hypothesis import settings as hypothesis_settings
from hypothesis import strategies as st
from schemathesis import Case, CheckFunction
from schemathesis.checks import CHECKS as CHECKS_REGISTRY
from schemathesis.checks import load_all_checks, not_a_server_error

# Checks register lazily; the deep profile resolves two of them by name below.
load_all_checks()

BACKEND_ROOT = Path(__file__).resolve().parent

# `format: uri` is the single most expensive thing in this schema to generate.
# hypothesis-jsonschema satisfies it by generating strings and filtering, and
# almost everything it generates fails the filter — one operation spent 78s to
# find five examples. Building URLs directly instead makes generation ~free and
# produces better inputs than the filter ever did: the host list deliberately
# mixes public names with loopback, link-local and private addresses so the
# link validator's rejection path is exercised, not just its happy path.
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
	"auth_sessions_destroy": "can revoke the fuzzer's own session",
	"accounts_users_change_password_create": "rotates the fuzzer's own password",
	"accounts_users_update": "can rotate the fuzzer's password via a full update",
	"accounts_users_partial_update": "can rotate the fuzzer's password",
	"accounts_users_destroy": "can delete the fuzzer's own user",
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

# Two checks cannot work against this harness and are excluded rather than left
# to cry wolf. Both ask "does the API reject a request with the auth removed?",
# and both are defeated the same way: we hand Schemathesis a pre-authenticated
# ``requests.Session``, whose cookie jar re-attaches ``notif_session`` to every
# request after Schemathesis has stripped it. The endpoint then answers 200 and
# the check reports an auth bypass that does not exist. Fixing this properly
# means registering a ``@schemathesis.auth()`` provider so Schemathesis owns the
# credential and can genuinely remove it; that is follow-up work, not a silent
# omission.
# cast: the registry is typed to also hand back check *classes*, but these two
# are registered as plain functions and that is what call_and_validate accepts.
EXCLUDED_CHECKS = cast(
	"list[CheckFunction]", list(CHECKS_REGISTRY.get_by_names(["ignored_auth", "negative_data_rejection"]))
)

# Phase selection is what actually decides the runtime, far more than
# ``max_examples``. Measured on POST /api/v1/monitoring/links/: the ``fuzzing``
# phase costs ~1s, the ``coverage`` phase ~32s, and ``coverage`` is insensitive
# to ``max_examples`` because it deterministically enumerates schema edge cases
# (missing required fields, wrong types, boundary values) rather than sampling.
# So CI takes the cheap randomized phase and the deep profile buys the thorough
# systematic one. Dropping ``coverage`` from CI is the difference between a 20s
# job and a 3-minute one.
PHASES = ["examples", "coverage", "fuzzing", "stateful"] if _IS_DEEP else ["fuzzing"]

schema = schemathesis.openapi.from_path(BACKEND_ROOT / "openapi.json").exclude(operation_id=list(UNFUZZABLE_OPERATIONS))
schema.config.phases.update(phases=PHASES)

FUZZ_USERNAME = "fuzzer"
FUZZ_PASSWORD = "fuzzer-pass-123"  # pragma: allowlist secret
FUZZ_EMAIL = "fuzzer@example.com"


@pytest.fixture
def fuzz_session(live_server: Any, django_user_model: Any) -> Iterator[requests.Session]:
	"""An authenticated ``requests`` session for the fuzzer to reuse.

	Function-scoped, so it costs one user creation and one login per *operation*
	rather than per generated example. The session cookie is Secure by design and
	``requests`` honours that strictly over plain HTTP (unlike Chromium's loopback
	exception), so the flag is overridden exactly as in the conformance trial or
	the cookie would never be sent back.
	"""
	with override_settings(SESSION_TOKEN_COOKIE_SECURE=False):
		django_user_model.objects.create_user(
			username=FUZZ_USERNAME,
			password=FUZZ_PASSWORD,
			email=FUZZ_EMAIL,
		)
		session = requests.Session()
		login = session.post(
			f"{live_server.url}/api/v1/auth/login/",
			json={"username": FUZZ_USERNAME, "password": FUZZ_PASSWORD, "transport": "cookie"},
			timeout=10,
		)
		assert login.status_code == 200, login.text
		# Cookie-transport writes enforce CSRF; login hands out a readable
		# csrftoken cookie exactly so clients can echo it back.
		session.headers["X-CSRFToken"] = session.cookies["csrftoken"]
		yield session
		session.close()


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
def test_operation_survives_generated_input(
	case: Case[Any],
	live_server: Any,
	fuzz_session: requests.Session,
) -> None:
	# transaction=True is required: live_server serves from a separate thread and
	# connection, so the fuzzing user must be committed for its login to be seen.
	case.call_and_validate(
		base_url=live_server.url,
		session=fuzz_session,
		checks=CHECKS,
		excluded_checks=EXCLUDED_CHECKS,
	)
