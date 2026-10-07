"""Unit tests for classify_fuzz_report: which deep fuzz failures are findings and which break the run.

Reports are built from the JUnit properties backend/conftest.py records; test_fuzz_verdict_hook.py
checks that the hook records them.
"""

import xml.etree.ElementTree as ET
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

import pytest
from classify_fuzz_report import (
	CANARY,
	CHECK,
	EXCEPTION,
	FINDING,
	OPERATION_TEST,
	REGRESSION_TEST,
	TIMEOUT,
	VERDICT,
	classify,
	main,
)
from hypothesis import HealthCheck, given, settings
from hypothesis import strategies as st

Properties = tuple[tuple[str, str], ...]


@dataclass(frozen=True)
class Case:
	name: str
	outcome: str | None = None  # "failure", "error", "skipped", or None for a pass
	properties: Properties = ()
	message: str = "boom"


def _operation(label: str, outcome: str | None = None, properties: Properties = ()) -> Case:
	return Case(f"{OPERATION_TEST}[{label}]", outcome, properties)


def _finding(*checks: str) -> Properties:
	return ((VERDICT, FINDING), *((CHECK, check) for check in checks))


def _not_a_finding(exception: str) -> Properties:
	return ((VERDICT, "not_a_finding"), (EXCEPTION, exception))


REGRESSION_PASSED = Case(REGRESSION_TEST)
HEALTH_PASSED = _operation("GET /api/v1/ops/health/")


def _write_report(tmp_path: Path, cases: list[Case]) -> Path:
	suite = ET.Element("testsuite", name="pytest", tests=str(len(cases)))
	for case in cases:
		element = ET.SubElement(suite, "testcase", classname="test_api_fuzz", name=case.name, time="1.0")
		if case.properties:
			properties = ET.SubElement(element, "properties")
			for name, value in case.properties:
				ET.SubElement(properties, "property", name=name, value=value)
		if case.outcome is not None:
			ET.SubElement(element, case.outcome, message=case.message).text = "traceback"
	root = ET.Element("testsuites", name="pytest tests")
	root.append(suite)
	path = tmp_path / "fuzz-report.xml"
	ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)
	return path


def _sound_report_with(tmp_path: Path, *cases: Case) -> Path:
	return _write_report(tmp_path, [REGRESSION_PASSED, HEALTH_PASSED, *cases])


def test_findings_alone_pass_and_are_counted_per_operation(tmp_path: Path) -> None:
	report = _sound_report_with(
		tmp_path,
		_operation("POST /users/", "failure", _finding("RejectedPositiveData")),
		_operation("POST /links/", "failure", _finding("RejectedPositiveData")),
		_operation("GET /users/", "failure", _finding("ServerError", "UndefinedStatusCode")),
	)

	verdict = classify(report, pytest_exit_code=1)

	assert verdict.problems == []
	assert (verdict.operations, verdict.passed, verdict.failed) == (4, 1, 3)
	assert verdict.findings_by_check == {"RejectedPositiveData": 2, "ServerError": 1, "UndefinedStatusCode": 1}
	assert verdict.findings_by_operation["GET /users/"] == ["ServerError", "UndefinedStatusCode"]


def test_a_clean_run_passes(tmp_path: Path) -> None:
	verdict = classify(_sound_report_with(tmp_path), pytest_exit_code=0)

	assert verdict.problems == []
	assert (verdict.operations, verdict.passed, verdict.failed) == (1, 1, 0)


def test_a_failure_that_is_not_a_finding_fails_the_run_and_is_named_by_type(tmp_path: Path) -> None:
	failure = _operation("POST /links/", "failure", _not_a_finding("requests.exceptions.ConnectionError"))

	verdict = classify(_sound_report_with(tmp_path, failure), pytest_exit_code=1)

	assert len(verdict.problems) == 1
	assert "POST /links/" in verdict.problems[0]
	assert "requests.exceptions.ConnectionError is not a Schemathesis check failure" in verdict.problems[0]
	assert verdict.findings_by_check == {}


def test_a_failure_without_a_verdict_fails_the_run(tmp_path: Path) -> None:
	verdict = classify(_sound_report_with(tmp_path, _operation("POST /links/", "failure")), pytest_exit_code=1)

	assert len(verdict.problems) == 1
	assert f"no {VERDICT} property" in verdict.problems[0]


def test_a_finding_verdict_without_checks_fails_the_run(tmp_path: Path) -> None:
	failure = _operation("POST /links/", "failure", _finding())

	verdict = classify(_sound_report_with(tmp_path, failure), pytest_exit_code=1)

	assert len(verdict.problems) == 1
	assert verdict.findings_by_check == {}


@pytest.mark.parametrize(
	("properties", "other_problems", "findings"),
	[
		(((CANARY, "credential"), *_not_a_finding("conftest.FuzzCanaryError")), 1, {}),
		# A FailureGroup on a later example replaced the canary's exception.
		(((CANARY, "credential"), *_finding("ServerError")), 0, {"ServerError": 1}),
	],
	ids=["canary-raised-last", "canary-masked-by-a-finding"],
)
def test_a_fired_canary_fails_the_run(
	tmp_path: Path, properties: Properties, other_problems: int, findings: dict[str, int]
) -> None:
	report = _sound_report_with(tmp_path, _operation("POST /links/", "failure", properties))

	verdict = classify(report, pytest_exit_code=1)

	assert f"{OPERATION_TEST}[POST /links/]: the credential canary fired" in verdict.problems
	assert len(verdict.problems) == 1 + other_problems
	assert verdict.findings_by_check == findings


@pytest.mark.parametrize(
	("outcome", "properties", "other_problems"),
	[
		("failure", ((TIMEOUT, "1800"), *_finding("ServerError")), 0),
		("failure", ((TIMEOUT, "1800"), *_not_a_finding("_pytest.outcomes.Failed")), 1),
		(None, ((TIMEOUT, "1800"),), 0),
	],
	ids=["masked-by-a-finding", "raised-last", "passed"],
)
def test_a_reached_timeout_fails_the_run(
	tmp_path: Path, outcome: str | None, properties: Properties, other_problems: int
) -> None:
	report = _sound_report_with(tmp_path, _operation("POST /links/", outcome, properties))

	verdict = classify(report, pytest_exit_code=0 if outcome is None else 1)

	timeout_problems = [problem for problem in verdict.problems if "1800 s timeout" in problem]
	assert len(timeout_problems) == 1
	assert len(verdict.problems) == 1 + other_problems


@pytest.mark.parametrize("phase", ["setup", "teardown"])
def test_an_error_fails_the_run_whatever_its_properties(tmp_path: Path, phase: str) -> None:
	# A teardown error after a finding carries the call's finding verdict.
	error = Case(f"{OPERATION_TEST}[POST /links/]", "error", _finding("ServerError"), f"failed on {phase}")

	verdict = classify(_sound_report_with(tmp_path, error), pytest_exit_code=1)

	assert len(verdict.problems) == 1
	assert f"failed on {phase}" in verdict.problems[0]
	assert verdict.findings_by_check == {}


def test_a_failing_test_that_is_not_an_operation_fails_the_run(tmp_path: Path) -> None:
	failure = Case("test_no_auth_provider_expects_a_reauth_replay", "failure")

	verdict = classify(_sound_report_with(tmp_path, failure), pytest_exit_code=1)

	assert len(verdict.problems) == 1
	assert "not a fuzzed operation" in verdict.problems[0]


def test_a_failing_live_server_regression_test_fails_the_run(tmp_path: Path) -> None:
	report = _write_report(
		tmp_path,
		[
			Case(REGRESSION_TEST, "failure", message="AssertionError: assert None is ..."),
			_operation("POST /users/", "failure", _finding("ServerError")),
		],
	)

	verdict = classify(report, pytest_exit_code=1)

	assert verdict.problems == [f"{REGRESSION_TEST} failed: AssertionError: assert None is ..."]


def test_a_missing_live_server_regression_test_fails_the_run(tmp_path: Path) -> None:
	verdict = classify(_write_report(tmp_path, [HEALTH_PASSED]), pytest_exit_code=0)

	assert verdict.problems == [f"{REGRESSION_TEST} is missing from the report"]


def test_an_empty_run_fails(tmp_path: Path) -> None:
	verdict = classify(_write_report(tmp_path, []), pytest_exit_code=5)

	assert any("collected no operation" in problem for problem in verdict.problems)
	assert any("exited with 5" in problem for problem in verdict.problems)


def test_a_run_without_operations_fails_even_when_pytest_exits_0(tmp_path: Path) -> None:
	verdict = classify(_write_report(tmp_path, [REGRESSION_PASSED]), pytest_exit_code=0)

	assert verdict.problems == ["pytest collected no operation to fuzz"]


@pytest.mark.parametrize("exit_code", [2, 3, 4, 5])
def test_a_pytest_exit_code_of_2_or_more_fails_the_run(tmp_path: Path, exit_code: int) -> None:
	report = _sound_report_with(tmp_path, _operation("POST /users/", "failure", _finding("ServerError")))

	verdict = classify(report, pytest_exit_code=exit_code)

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
	finding = [_operation("POST /users/", "failure", _finding("ServerError"))] if with_finding else []

	verdict = classify(_sound_report_with(tmp_path, *finding), pytest_exit_code=exit_code)

	assert len(verdict.problems) == 1
	assert "disagrees" in verdict.problems[0]


@pytest.mark.parametrize("content", [None, "<testsuites><testsuite>"], ids=["missing", "malformed"])
def test_an_unreadable_report_fails_the_run(tmp_path: Path, content: str | None) -> None:
	report = tmp_path / "fuzz-report.xml"
	if content is not None:
		report.write_text(content, encoding="utf-8")

	verdict = classify(report, pytest_exit_code=1)

	assert len(verdict.problems) == 1
	assert "cannot read" in verdict.problems[0]


def test_main_exits_0_on_findings_and_writes_a_summary(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
	report = _sound_report_with(tmp_path, _operation("POST /users/", "failure", _finding("RejectedPositiveData")))

	exit_code = main([str(report), "--pytest-exit-code", "1"])

	summary = capsys.readouterr().out
	assert exit_code == 0
	assert "| 2 | 1 | 1 | 0 |" in summary
	assert "| `RejectedPositiveData` | 1 |" in summary
	assert "- `POST /users/`: `RejectedPositiveData`" in summary


def test_main_exits_1_on_a_problem_and_names_it(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
	canary = _operation("POST /links/", "failure", ((CANARY, "csrf"), *_not_a_finding("conftest.FuzzCanaryError")))

	exit_code = main([str(_sound_report_with(tmp_path, canary)), "--pytest-exit-code", "1"])

	summary = capsys.readouterr().out
	assert exit_code == 1
	assert "**The run is unsound.**" in summary
	assert "the csrf canary fired" in summary


@dataclass(frozen=True)
class _Operation:
	outcome: str | None
	verdict: str | None  # FINDING, "not_a_finding", or None for no verdict property
	checks: tuple[str, ...]
	canary: bool
	timeout: bool


_OPERATIONS = st.builds(
	_Operation,
	outcome=st.sampled_from([None, "skipped", "failure", "error"]),
	verdict=st.sampled_from([FINDING, "not_a_finding", None]),
	checks=st.lists(st.sampled_from(["ServerError", "UndefinedStatusCode", "IgnoredAuth"]), max_size=2).map(tuple),
	canary=st.booleans(),
	timeout=st.booleans(),
)


@settings(suppress_health_check=[HealthCheck.function_scoped_fixture], deadline=None)
@given(
	operations=st.lists(_OPERATIONS, max_size=4),
	regression=st.sampled_from(["passed", "failed", "missing"]),
	exit_code=st.sampled_from([0, 1, 2]),
)
def test_the_run_is_sound_exactly_when_every_rule_holds(
	tmp_path: Path, operations: list[_Operation], regression: str, exit_code: int
) -> None:
	cases = [] if regression == "missing" else [Case(REGRESSION_TEST, "failure" if regression == "failed" else None)]
	for number, op in enumerate(operations):
		properties: list[tuple[str, str]] = []
		if op.verdict is not None:
			properties.append((VERDICT, op.verdict))
		properties += [(CHECK, check) for check in op.checks]
		properties += [(CANARY, "credential")] * op.canary + [(TIMEOUT, "1800")] * op.timeout
		cases.append(_operation(f"op{number}", op.outcome, tuple(properties)))

	verdict = classify(_write_report(tmp_path, cases), pytest_exit_code=exit_code)

	# Restated from docs/testing.md, independently of the classifier's code.
	failed = [op.outcome in {"failure", "error"} for op in operations]
	findings = [op for op in operations if op.outcome == "failure" and op.verdict == FINDING and op.checks]
	sound = (
		exit_code == int(any(failed) or regression == "failed")
		and regression == "passed"
		and bool(operations)
		and not any(op.canary or op.timeout for op in operations)
		and sum(failed) == len(findings)
	)
	assert (verdict.problems == []) == sound, verdict.problems
	assert verdict.findings_by_check == Counter(check for op in findings for check in set(op.checks))
	assert (verdict.operations, verdict.failed) == (len(operations), sum(failed))
