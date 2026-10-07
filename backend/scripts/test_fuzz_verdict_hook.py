"""The deep fuzz verdict hook in backend/conftest.py, end to end through pytest and the classifier.

Each shape is a real ``@given`` test raising real Schemathesis exceptions, run by an inner pytest with
the backend conftest as a plugin. Why the shapes matter: docs/testing.md.
"""

import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

import classify_fuzz_report
import pytest
import requests
import schemathesis
from schemathesis.core.failures import Failure, FailureGroup

import conftest
import test_api_fuzz
from conftest import FUZZ_CANARY, FUZZ_CHECK, FUZZ_EXCEPTION, FUZZ_OPERATION_TEST, FUZZ_TIMEOUT, FUZZ_VERDICT

pytest_plugins = ("pytester",)

_HEADER = """\
import time

import pytest
import requests
from hypothesis import HealthCheck, example, given, settings
from hypothesis import strategies as st
from schemathesis.core.failures import FailureGroup, ServerError
from schemathesis.openapi.checks import UndefinedStatusCode

CALLS = []
SETTINGS = settings(
    database=None, derandomize=True, max_examples=20, deadline=None,
    suppress_health_check=[HealthCheck.function_scoped_fixture],
)


def failure_group(*extra):
    return FailureGroup([
        ServerError(operation="GET /x", status_code=500),
        UndefinedStatusCode(
            operation="GET /x", status_code=418, defined_status_codes=["200"], allowed_status_codes=[200], message="m"
        ),
        *extra,
    ])


def first_call():
    CALLS.append(None)
    return len(CALLS) == 1

"""


def _shape(name: str, body: str, decorators: str = "", fixtures: str = "") -> str:
	return f"""{_HEADER}
@pytest.mark.parametrize("shape", ["{name}"])
@SETTINGS
{decorators}@given(x=st.integers(min_value=0))
def {FUZZ_OPERATION_TEST}(shape, x, fuzz_canary{fixtures}):
    {body}
"""


SHAPES = {
	"finding": _shape("finding", "raise failure_group()"),
	"canary": _shape("canary", 'fuzz_canary("credential", "fuzzer credential was rejected")'),
	# Claessen's d2: the canary's AssertionError, then a FailureGroup that Hypothesis re-raises instead.
	"canary_then_finding": _shape(
		"canary_then_finding",
		'if first_call():\n        fuzz_canary("credential", "fuzzer credential was rejected")\n    raise failure_group()',
	),
	# Claessen's g2: what pytest-timeout's signal method raises inside the test, then a FailureGroup.
	"timeout_then_finding": _shape(
		"timeout_then_finding",
		"if first_call():\n        time.sleep(0.1)\n"
		'        pytest.fail("Timeout (>0.05s) from pytest-timeout.")\n    raise failure_group()',
		decorators="@pytest.mark.timeout(0.05)\n",
	),
	"non_failure_member": _shape("non_failure_member", 'raise failure_group(RuntimeError("not a check"))'),
	# Two bare check failures that Hypothesis reports as distinct bugs: a group of Failures, not a FailureGroup.
	"bare_failures": _shape(
		"bare_failures",
		'if x % 2:\n        raise ServerError(operation="GET /x", status_code=500)\n'
		'    raise UndefinedStatusCode(operation="GET /x", status_code=418, defined_status_codes=["200"],'
		' allowed_status_codes=[200], message="m")',
	),
	"connection_error": _shape("connection_error", 'raise requests.exceptions.ConnectionError("Max retries exceeded")'),
	"setup_error": _shape("setup_error", "raise failure_group()", fixtures=", broken")
	+ '\n@pytest.fixture\ndef broken():\n    raise RuntimeError("setup broke")\n',
	"explicit_grouping": _shape(
		"explicit_grouping",
		'if x == -1:\n        raise AssertionError("an explicit example failed")\n    raise failure_group()',
		decorators="@example(x=-1)\n@example(x=-2)\n",
	),
	"passes": _shape("passes", "pass"),
	# Starts with the gated name but is another test: the hook must leave it alone.
	"twin": f"{_HEADER}\ndef {FUZZ_OPERATION_TEST}_twin():\n    raise failure_group()\n",
	"regression": f"def {classify_fuzz_report.REGRESSION_TEST}():\n    pass\n",
}

_GROUP_CHECKS = [(FUZZ_CHECK, "ServerError"), (FUZZ_CHECK, "UndefinedStatusCode")]
EXPECTED = {
	"finding": ("failure", [(FUZZ_VERDICT, "finding"), *_GROUP_CHECKS]),
	"canary": (
		"failure",
		[(FUZZ_CANARY, "credential"), (FUZZ_VERDICT, "not_a_finding"), (FUZZ_EXCEPTION, "conftest.FuzzCanaryError")],
	),
	"canary_then_finding": ("failure", [(FUZZ_CANARY, "credential"), (FUZZ_VERDICT, "finding"), *_GROUP_CHECKS]),
	"timeout_then_finding": ("failure", [(FUZZ_VERDICT, "finding"), *_GROUP_CHECKS, (FUZZ_TIMEOUT, "0.05")]),
	"non_failure_member": (
		"failure",
		[(FUZZ_VERDICT, "not_a_finding"), (FUZZ_EXCEPTION, "schemathesis.core.failures.FailureGroup")],
	),
	"bare_failures": ("failure", [(FUZZ_VERDICT, "not_a_finding"), (FUZZ_EXCEPTION, "builtins.ExceptionGroup")]),
	"connection_error": (
		"failure",
		[(FUZZ_VERDICT, "not_a_finding"), (FUZZ_EXCEPTION, "requests.exceptions.ConnectionError")],
	),
	"setup_error": ("error", []),
	"explicit_grouping": (
		"failure",
		[(FUZZ_VERDICT, "not_a_finding"), (FUZZ_EXCEPTION, "builtins.BaseExceptionGroup")],
	),
	"passes": ("passed", []),
}


class _NoTimer:
	"""Stands in for pytest-timeout's timer, so a tiny budget never interrupts the inner run for real."""

	@pytest.hookimpl
	def pytest_timeout_set_timer(self, item: pytest.Item, settings: Any) -> bool:
		return True


def _run_shapes(pytester: pytest.Pytester) -> tuple[pytest.HookRecorder, Path]:
	pytester.makeini("[pytest]\n")
	pytester.makepyfile(**{f"test_{name}": source for name, source in SHAPES.items()})
	junit = pytester.path / "report.xml"
	recorder = pytester.inline_run(
		"-p",
		"no:django",
		"-p",
		"no:randomly",
		"-p",
		"no:cacheprovider",
		"--timeout=600",
		f"--junitxml={junit}",
		plugins=[conftest, _NoTimer()],
	)
	return recorder, junit


def _outcomes(junit: Path) -> dict[str, tuple[str, list[tuple[str, str]]]]:
	outcomes = {}
	for case in ET.parse(junit).getroot().iter("testcase"):
		kinds = [child.tag for child in case if child.tag in {"failure", "error", "skipped"}]
		properties = [(prop.get("name", ""), prop.get("value", "")) for prop in case.iter("property")]
		label = case.get("name", "").removeprefix(f"{FUZZ_OPERATION_TEST}[").removesuffix("]")
		outcomes[label] = (kinds[0] if kinds else "passed", properties)
	return outcomes


def test_the_hook_records_each_shape_and_the_classifier_reads_it(pytester: pytest.Pytester) -> None:
	recorder, junit = _run_shapes(pytester)

	outcomes = _outcomes(junit)
	assert {label: outcomes[label] for label in EXPECTED} == EXPECTED
	assert outcomes[f"{FUZZ_OPERATION_TEST}_twin"] == ("failure", [])
	# execnet serialises by exact type, so anything but a plain str breaks under xdist.
	reports = recorder.getreports("pytest_runtest_logreport")
	assert {(type(name), type(value)) for report in reports for name, value in report.user_properties} == {(str, str)}

	assert recorder.ret == pytest.ExitCode.TESTS_FAILED
	verdict = classify_fuzz_report.classify(junit, pytest_exit_code=pytest.ExitCode.TESTS_FAILED)
	problem_labels = {problem.partition(":")[0] for problem in verdict.problems}
	assert problem_labels == {
		*(f"{FUZZ_OPERATION_TEST}[{label}]" for label in EXPECTED if label not in {"finding", "passes"}),
		f"{FUZZ_OPERATION_TEST}_twin",
	}
	assert sorted(verdict.findings_by_operation) == ["canary_then_finding", "finding", "timeout_then_finding"]


def test_the_gate_and_the_classifier_name_the_real_tests() -> None:
	assert FUZZ_OPERATION_TEST == classify_fuzz_report.OPERATION_TEST
	for name in (FUZZ_OPERATION_TEST, classify_fuzz_report.REGRESSION_TEST):
		assert callable(getattr(test_api_fuzz, name, None)), name
	vocabulary = (FUZZ_VERDICT, FUZZ_CHECK, FUZZ_EXCEPTION, FUZZ_CANARY, FUZZ_TIMEOUT)
	assert vocabulary == (
		classify_fuzz_report.VERDICT,
		classify_fuzz_report.CHECK,
		classify_fuzz_report.EXCEPTION,
		classify_fuzz_report.CANARY,
		classify_fuzz_report.TIMEOUT,
	)


def test_validate_response_raises_a_failure_group_of_failures_on_a_500() -> None:
	"""Pins the internal Schemathesis types the hook relies on: neither has a public import path in 4.24."""
	raw_schema = {
		"openapi": "3.0.3",
		"info": {"title": "contract", "version": "1"},
		"paths": {"/items": {"get": {"responses": {"200": {"description": "OK"}}}}},
	}
	case = schemathesis.openapi.from_dict(raw_schema)["/items"]["GET"].Case()
	response = requests.Response()
	response.status_code = 500
	response._content = b"{}"
	response.url = "http://127.0.0.1/items"
	response.request = requests.Request("GET", response.url).prepare()

	with pytest.raises(FailureGroup) as raised:
		case.validate_response(response)

	members = raised.value.exceptions
	# Hypothesis catches only Exception and a few others; a BaseException ends the test: see docs/testing.md.
	assert not isinstance(raised.value, Exception)
	assert "ServerError" in {type(member).__name__ for member in members}
	assert all(isinstance(member, Failure) for member in members)
