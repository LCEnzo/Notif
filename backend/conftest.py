"""Pytest-wide fixtures for the backend suite."""

import time
from collections.abc import Callable, Generator
from typing import Any, NoReturn

import pytest

import monitoring.safe_fetch as safe_fetch

# The deep fuzz verdict: JUnit properties that scripts/classify_fuzz_report.py reads. See docs/testing.md.
FUZZ_OPERATION_TEST = "test_operation_survives_generated_input"
FUZZ_VERDICT = "fuzz_verdict"
FUZZ_CHECK = "fuzz_check"
FUZZ_EXCEPTION = "fuzz_exception"
FUZZ_CANARY = "fuzz_canary"
FUZZ_TIMEOUT = "fuzz_timeout"
_FUZZ_TIMER = pytest.StashKey[tuple[float, float]]()


@pytest.fixture(scope="session")
def live_server(django_db_setup: None, live_server: Any) -> Any:
	"""Start the live server only after the test database exists, or its request threads leak connections.

	pytest-django shares the in-memory SQLite connection only if the database is in memory at server start.
	"""
	return live_server


def _resolve_nothing(host: str) -> list[str]:
	return []


@pytest.fixture(autouse=True)
def _bypass_public_host_resolution_for_mocked_network(
	request: pytest.FixtureRequest, monkeypatch: pytest.MonkeyPatch
) -> None:
	"""Keep the broad suite off real DNS and the real network.

	The replacement resolves every host to no addresses, so a test that
	reaches the guarded transport without a mock (``requests_mock`` replaces
	the adapter, so mocked tests never get there) fails with a
	``requests.ConnectionError`` instead of resolving and dialling out.

	Tests that exercise the guard itself carry the ``real_ssrf`` marker and are
	exempted: they run against the real resolver by default, so a new guard test
	cannot silently pass against a disabled guard by forgetting to restore it.
	"""
	if request.node.get_closest_marker("real_ssrf"):
		return
	monkeypatch.setattr(safe_fetch, "resolve_public_host", _resolve_nothing)


class FuzzCanaryError(AssertionError):
	"""A fuzz canary fired: generated requests are not reaching the handler."""


@pytest.fixture
def fuzz_canary(request: pytest.FixtureRequest) -> Callable[[str, str], NoReturn]:
	"""Fail the fuzz test, recording the canary on the item first so that no later exception can hide it."""

	def fire(name: str, message: str) -> NoReturn:
		if (FUZZ_CANARY, name) not in request.node.user_properties:
			request.node.user_properties.append((FUZZ_CANARY, name))
		raise FuzzCanaryError(message)

	return fire


def _is_fuzz_operation(item: pytest.Item) -> bool:
	return isinstance(item, pytest.Function) and item.originalname == FUZZ_OPERATION_TEST


def _verdict(exc: BaseException) -> list[tuple[str, str]]:
	from schemathesis.core.failures import Failure, FailureGroup  # noqa: PLC0415 - only fuzz operations import it

	if isinstance(exc, FailureGroup) and all(isinstance(member, Failure) for member in exc.exceptions):
		checks = sorted({type(member).__name__ for member in exc.exceptions})
		return [(FUZZ_VERDICT, "finding"), *((FUZZ_CHECK, check) for check in checks)]
	return [(FUZZ_VERDICT, "not_a_finding"), (FUZZ_EXCEPTION, f"{type(exc).__module__}.{type(exc).__qualname__}")]


# tryfirst: an observer; the first impl to return a result ends this firstresult hook.
@pytest.hookimpl(tryfirst=True, optionalhook=True)
def pytest_timeout_set_timer(item: pytest.Item, settings: Any) -> None:
	"""Note when pytest-timeout arms a fuzz operation's timer, and with what budget."""
	if _is_fuzz_operation(item):
		item.stash[_FUZZ_TIMER] = (time.perf_counter(), float(settings.timeout))


@pytest.hookimpl(wrapper=True)
def pytest_runtest_makereport(
	item: pytest.Item, call: pytest.CallInfo[None]
) -> Generator[None, pytest.TestReport, pytest.TestReport]:
	"""Record a fuzz operation's verdict and timeout as JUnit properties.

	Appended before the report exists: each report copies the item's properties when it is built.
	"""
	if _is_fuzz_operation(item):
		if call.when == "call" and call.excinfo is not None:
			item.user_properties.extend(_verdict(call.excinfo.value))
		if call.when == "teardown" and (timer := item.stash.get(_FUZZ_TIMER, None)) is not None:
			armed_at, budget = timer
			if time.perf_counter() - armed_at >= budget:
				item.user_properties.append((FUZZ_TIMEOUT, f"{budget:g}"))
	return (yield)
