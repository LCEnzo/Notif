"""Unit tests for classify_fuzz_report: which deep fuzz failures are findings and which break the run.

The failure texts are trimmed from real JUnit reports: a deep run of test_api_fuzz.py and a
scratch module raising Schemathesis 4.24.3's own failure classes under Hypothesis 6.168.1.
"""

import xml.etree.ElementTree as ET
from pathlib import Path

import classify_fuzz_report
import pytest
from classify_fuzz_report import OPERATION_TEST, REGRESSION_TEST, classify, main

FINDING_ONE_CHECK = """\
+ Exception Group Traceback (most recent call last):
  |   File "/runner/backend/.venv/lib/python3.14/site-packages/schemathesis/generation/case.py", line 601, in call_and_validate
  |     self.validate_response(
  |     ~~~~~~~~~~~~~~~~~~~~~~^
  |   File "/runner/backend/.venv/lib/python3.14/site-packages/schemathesis/generation/case.py", line 560, in validate_response
  |     raise FailureGroup(_failures, message) from None
  | schemathesis.core.failures.FailureGroup: Schemathesis found 1 distinct failure
  |
  | - API rejected schema-compliant request
  |
  |     Valid data should have been accepted
  |     Expected: 2xx, 401, 403, 404, 409, 5xx
  |
  | [400] Bad Request:
  |
  |     `{"non_field_errors":["This password is entirely numeric."]}`
  |
  |  (1 sub-exception)
  +-+---------------- 1 ----------------
    | schemathesis.openapi.checks.RejectedPositiveData: API rejected schema-compliant request
    |
    | Valid data should have been accepted
    | Expected: 2xx, 401, 403, 404, 409, 5xx
    +------------------------------------"""

FINDING_TWO_CHECKS = """\
+ Exception Group Traceback (most recent call last):
  |   File "/runner/backend/.venv/lib/python3.14/site-packages/schemathesis/generation/case.py", line 560, in validate_response
  |     raise FailureGroup(_failures, message) from None
  | schemathesis.core.failures.FailureGroup: Schemathesis found 2 distinct failures
  |
  | - Undocumented HTTP status code
  |
  | - Server error
  |  (2 sub-exceptions)
  +-+---------------- 1 ----------------
    | schemathesis.openapi.checks.UndefinedStatusCode: Undocumented HTTP status code
    |
    | Received: 405
    | Documented: 200
    +---------------- 2 ----------------
    | schemathesis.core.failures.ServerError: Server error
    +------------------------------------"""

# A pytest-long-format failure: the canary asserted outside any exception group.
CANARY_CREDENTIAL = """\
test_api_fuzz.py:196: in test_operation_survives_generated_input
    assert not (response.status_code == 401 and _requires_auth(case)), (
E   AssertionError: fuzzer credential was rejected; generated requests are not reaching the handler: {"detail":"Authentication credentials were not provided."}
E   assert not (401 == 401 and True)"""

CANARY_CSRF = """\
test_api_fuzz.py:200: in test_operation_survives_generated_input
    assert not (response.status_code == 403 and "CSRF Failed" in response.text), (
E   AssertionError: fuzzer CSRF token was rejected; generated writes are not reaching the handler: {"detail":"CSRF Failed: CSRF token missing."}"""

# Hypothesis groups an Exception from one explicit example with the FailureGroup that ends the loop.
CANARY_BESIDE_FINDING = """\
+ Exception Group Traceback (most recent call last):
  |   File "/runner/backend/.venv/lib/python3.14/site-packages/hypothesis/core.py", line 1691, in _raise_to_user
  |     raise the_error_hypothesis_found
  | BaseExceptionGroup: Hypothesis found 2 distinct failures in explicit examples. (2 sub-exceptions)
  +-+---------------- 1 ----------------
    | Traceback (most recent call last):
    |   File "/runner/backend/test_api_fuzz.py", line 196, in test_operation_survives_generated_input
    |     assert not (response.status_code == 401 and _requires_auth(case)), (
    | AssertionError: fuzzer credential was rejected; generated requests are not reaching the handler: {}
    +---------------- 2 ----------------
    | Exception Group Traceback (most recent call last):
    |   File "/runner/backend/.venv/lib/python3.14/site-packages/schemathesis/generation/case.py", line 560, in validate_response
    |     raise FailureGroup(_failures, message) from None
    | schemathesis.core.failures.FailureGroup: Schemathesis found 1 distinct failure
    |  (1 sub-exception)
    +-+---------------- 1 ----------------
      | schemathesis.openapi.checks.UndefinedStatusCode: Undocumented HTTP status code
      +------------------------------------"""

CONNECTION_ERROR = """\
test_api_fuzz.py:190: in test_operation_survives_generated_input
    response = case.call_and_validate(
E   requests.exceptions.ConnectionError: HTTPConnectionPool(host='localhost', port=50123): Max retries exceeded"""

LIVE_SERVER_REGRESSION = """\
test_api_fuzz.py:156: in test_live_server_shares_the_test_database_connection
    assert live_server.thread.connections_override.get("default") is default
E   AssertionError: assert None is <DatabaseWrapper vendor='sqlite' alias='default'>"""

Outcome = tuple[str, str, str] | None  # (element tag, message attribute, text), or None for a pass


def _operation(label: str) -> str:
	return f"{OPERATION_TEST}[{label}]"


def _write_report(tmp_path: Path, cases: dict[str, Outcome]) -> Path:
	suite = ET.Element("testsuite", name="pytest", tests=str(len(cases)))
	for name, outcome in cases.items():
		case = ET.SubElement(suite, "testcase", classname="test_api_fuzz", name=name, time="1.0")
		if outcome is not None:
			tag, message, text = outcome
			ET.SubElement(case, tag, message=message).text = text
	root = ET.Element("testsuites", name="pytest tests")
	root.append(suite)
	path = tmp_path / "fuzz-report.xml"
	ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)
	return path


def _finding(text: str = FINDING_ONE_CHECK) -> Outcome:
	return ("failure", "RejectedPositiveData() [single exception in FailureGroup]", text)


def _report_with(tmp_path: Path, **extra: Outcome) -> Path:
	"""A sound run (regression test green, one operation passing) plus the given operations."""
	cases: dict[str, Outcome] = {REGRESSION_TEST: None, _operation("GET /api/v1/ops/health/"): None}
	cases.update({_operation(label): outcome for label, outcome in extra.items()})
	return _write_report(tmp_path, cases)


def test_findings_alone_pass_and_are_counted_per_check(tmp_path: Path) -> None:
	report = _report_with(
		tmp_path,
		post_users=_finding(),
		post_links=_finding(),
		get_users=("failure", "schemathesis.core.failures.FailureGroup: ...", FINDING_TWO_CHECKS),
	)

	verdict = classify(report, pytest_exit_code=1)

	assert verdict.problems == []
	assert (verdict.operations, verdict.passed, verdict.failed) == (4, 1, 3)
	assert verdict.findings_by_check == {
		"API rejected schema-compliant request (`RejectedPositiveData`)": 2,
		"Undocumented HTTP status code (`UndefinedStatusCode`)": 1,
		"Server error (`ServerError`)": 1,
	}


def test_a_clean_run_passes(tmp_path: Path) -> None:
	verdict = classify(_report_with(tmp_path), pytest_exit_code=0)

	assert verdict.problems == []
	assert (verdict.operations, verdict.passed, verdict.failed) == (1, 1, 0)


@pytest.mark.parametrize(
	("text", "expected"),
	[
		(CANARY_CREDENTIAL, "credential canary"),
		(CANARY_CSRF, "CSRF canary"),
		(CANARY_BESIDE_FINDING, "credential canary"),
	],
)
def test_a_canary_fails_the_run(tmp_path: Path, text: str, expected: str) -> None:
	report = _report_with(tmp_path, post_links=("failure", "AssertionError: ...", text))

	verdict = classify(report, pytest_exit_code=1)

	assert len(verdict.problems) == 1
	assert expected in verdict.problems[0]


@pytest.mark.parametrize("phase", ["setup", "teardown"])
def test_a_setup_or_teardown_error_fails_the_run(tmp_path: Path, phase: str) -> None:
	error = ("error", f'failed on {phase} with "RuntimeError: database setup failed"', "RuntimeError")
	report = _report_with(tmp_path, post_links=error)

	verdict = classify(report, pytest_exit_code=1)

	assert len(verdict.problems) == 1
	assert f"failed on {phase}" in verdict.problems[0]


def test_an_empty_run_fails(tmp_path: Path) -> None:
	verdict = classify(_write_report(tmp_path, {}), pytest_exit_code=5)

	assert any("collected no operation" in problem for problem in verdict.problems)
	assert any("exited with 5" in problem for problem in verdict.problems)


def test_a_run_without_operations_fails_even_when_pytest_exits_0(tmp_path: Path) -> None:
	verdict = classify(_write_report(tmp_path, {REGRESSION_TEST: None}), pytest_exit_code=0)

	assert verdict.problems == ["pytest collected no operation to fuzz"]


def test_a_mixed_report_fails_and_still_counts_its_findings(tmp_path: Path) -> None:
	report = _report_with(
		tmp_path,
		post_users=_finding(),
		post_links=("failure", "requests.exceptions.ConnectionError: ...", CONNECTION_ERROR),
	)

	verdict = classify(report, pytest_exit_code=1)

	assert len(verdict.problems) == 1
	assert "post_links" in verdict.problems[0]
	assert "ConnectionError" in verdict.problems[0]
	assert verdict.findings_by_check == {"API rejected schema-compliant request (`RejectedPositiveData`)": 1}


def test_a_finding_grouped_with_another_error_is_not_a_finding(tmp_path: Path) -> None:
	text = CANARY_BESIDE_FINDING.replace(
		"    | AssertionError: fuzzer credential was rejected; generated requests are not reaching the handler: {}",
		"    | requests.exceptions.ConnectionError: Max retries exceeded",
	)

	verdict = classify(_report_with(tmp_path, post_links=_finding(text)), pytest_exit_code=1)

	assert len(verdict.problems) == 1
	assert "not a Schemathesis check failure" in verdict.problems[0]
	assert verdict.findings_by_check == {}


def test_a_failing_live_server_regression_test_fails_the_run(tmp_path: Path) -> None:
	report = _write_report(
		tmp_path,
		{
			REGRESSION_TEST: ("failure", "AssertionError: assert None is ...", LIVE_SERVER_REGRESSION),
			_operation("POST /api/v1/accounts/users/"): _finding(),
		},
	)

	verdict = classify(report, pytest_exit_code=1)

	assert verdict.problems == [f"{REGRESSION_TEST} failed: AssertionError: assert None is ..."]


def test_a_missing_live_server_regression_test_fails_the_run(tmp_path: Path) -> None:
	report = _write_report(tmp_path, {_operation("GET /api/v1/ops/health/"): None})

	verdict = classify(report, pytest_exit_code=0)

	assert verdict.problems == [f"{REGRESSION_TEST} is missing from the report"]


@pytest.mark.parametrize("exit_code", [2, 3, 4, 5])
def test_a_pytest_exit_code_of_2_or_more_fails_the_run(tmp_path: Path, exit_code: int) -> None:
	verdict = classify(_report_with(tmp_path, post_users=_finding()), pytest_exit_code=exit_code)

	assert len(verdict.problems) == 1
	assert f"exited with {exit_code}" in verdict.problems[0]


@pytest.mark.parametrize(
	("exit_code", "with_finding"),
	[(1, False), (0, True)],
	ids=["exit-1-nothing-failed", "exit-0-with-a-finding"],
)
def test_an_exit_code_that_disagrees_with_the_report_fails_the_run(
	tmp_path: Path, exit_code: int, *, with_finding: bool
) -> None:
	report = _report_with(tmp_path, post_users=_finding()) if with_finding else _report_with(tmp_path)

	verdict = classify(report, pytest_exit_code=exit_code)

	assert len(verdict.problems) == 1
	assert "disagrees" in verdict.problems[0]


def test_a_failure_group_with_a_child_that_is_not_a_check_failure_is_not_a_finding(tmp_path: Path) -> None:
	text = FINDING_ONE_CHECK.replace(
		"    | schemathesis.openapi.checks.RejectedPositiveData: API rejected schema-compliant request",
		"    | Traceback (most recent call last):",
	)

	verdict = classify(_report_with(tmp_path, post_users=_finding(text)), pytest_exit_code=1)

	assert len(verdict.problems) == 1
	assert "post_users" in verdict.problems[0]


def test_children_elided_from_a_failure_group_still_count_as_findings(tmp_path: Path) -> None:
	text = FINDING_TWO_CHECKS.replace(
		"    | schemathesis.core.failures.ServerError: Server error",
		"    | and 3 more exceptions",
	).replace("+---------------- 2 ----------------", "+---------------- ... ----------------")

	verdict = classify(_report_with(tmp_path, get_users=_finding(text)), pytest_exit_code=1)

	assert verdict.problems == []
	assert verdict.findings_by_check == {
		"Undocumented HTTP status code (`UndefinedStatusCode`)": 1,
		"(not listed in the report)": 1,
	}


@pytest.mark.parametrize("content", [None, "<testsuites><testsuite>"], ids=["missing", "malformed"])
def test_an_unreadable_report_fails_the_run(tmp_path: Path, content: str | None) -> None:
	report = tmp_path / "fuzz-report.xml"
	if content is not None:
		report.write_text(content, encoding="utf-8")

	verdict = classify(report, pytest_exit_code=1)

	assert len(verdict.problems) == 1
	assert "cannot read" in verdict.problems[0]


def test_main_exits_0_on_findings_and_writes_a_summary(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
	report = _report_with(tmp_path, post_users=_finding())

	exit_code = main([str(report), "--pytest-exit-code", "1"])

	summary = capsys.readouterr().out
	assert exit_code == 0
	assert "| 2 | 1 | 1 | 0 |" in summary
	assert "| API rejected schema-compliant request (`RejectedPositiveData`) | 1 |" in summary


def test_main_exits_1_on_a_problem_and_names_it(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
	report = _report_with(tmp_path, post_links=("failure", "AssertionError: ...", CANARY_CSRF))

	exit_code = main([str(report), "--pytest-exit-code", "1"])

	summary = capsys.readouterr().out
	assert exit_code == 1
	assert "CSRF canary" in summary


def test_the_markers_still_match_the_fuzz_module() -> None:
	"""The classifier keys on names and canary messages that live in test_api_fuzz.py."""
	source = (Path(__file__).resolve().parents[1] / "test_api_fuzz.py").read_text(encoding="utf-8")

	assert f"def {REGRESSION_TEST}(" in source
	assert f"def {OPERATION_TEST}(" in source
	for phrase in classify_fuzz_report.CANARIES.values():
		assert phrase in source
