"""Tell a deep fuzz run's expected findings from a broken run, and summarise the run in Markdown.

Reads the JUnit XML that ``pytest test_api_fuzz.py --junitxml`` writes, and the properties that
backend/conftest.py records on each fuzzed operation. Exits 0 when every failure is a Schemathesis
check failure other than a canary, 1 when the run itself is unsound. Rules and sources: docs/testing.md.
"""

from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

OPERATION_TEST = "test_operation_survives_generated_input"
REGRESSION_TEST = "test_live_server_shares_the_test_database_connection"
# JUnit properties that backend/conftest.py records.
VERDICT = "fuzz_verdict"
FINDING = "finding"
CHECK = "fuzz_check"
EXCEPTION = "fuzz_exception"
CANARY = "fuzz_canary"
TIMEOUT = "fuzz_timeout"
_MAX_DETAIL = 300


@dataclass
class Verdict:
	problems: list[str] = field(default_factory=list)
	operations: int = 0
	passed: int = 0
	failed: int = 0
	skipped: int = 0
	findings_by_check: Counter[str] = field(default_factory=Counter)
	findings_by_operation: dict[str, list[str]] = field(default_factory=dict)


def _first_line(text: str) -> str:
	line = text.strip().partition("\n")[0]
	return line if len(line) <= _MAX_DETAIL else f"{line[:_MAX_DETAIL]}..."


def _properties(case: ET.Element, name: str) -> list[str]:
	return [prop.get("value", "") for prop in case.iter("property") if prop.get("name") == name]


def _classify_failure(case: ET.Element, failure: ET.Element, verdict: Verdict) -> None:
	name = case.get("name", "")
	message = _first_line(failure.get("message", ""))
	verdicts, checks = _properties(case, VERDICT), _properties(case, CHECK)
	if name == REGRESSION_TEST:
		verdict.problems.append(f"{REGRESSION_TEST} failed: {message}")
	elif not name.startswith(f"{OPERATION_TEST}["):
		verdict.problems.append(f"{name}: not a fuzzed operation: {message}")
	elif verdicts == [FINDING] and checks:
		verdict.findings_by_operation[name.removeprefix(f"{OPERATION_TEST}[").removesuffix("]")] = checks
		verdict.findings_by_check.update(set(checks))
	elif verdicts == [FINDING] and _properties(case, CANARY):
		return  # Only canary checks failed, and _classify_case already counts each canary as a problem.
	elif exceptions := _properties(case, EXCEPTION):
		verdict.problems.append(f"{name}: {', '.join(exceptions)} is not a Schemathesis check failure: {message}")
	elif not verdicts:
		verdict.problems.append(f"{name}: no {VERDICT} property, so the verdict hook did not run: {message}")
	else:
		verdict.problems.append(f"{name}: unexpected {VERDICT} {verdicts} with checks {checks}: {message}")


def _classify_case(case: ET.Element, verdict: Verdict) -> bool:
	"""Record one test case; True when it failed or errored."""
	name = case.get("name", "")
	error, failure = case.find("error"), case.find("failure")
	if error is not None:
		verdict.problems.append(f"{name}: {_first_line(error.get('message', 'error'))}")
	verdict.problems += [f"{name}: the {canary} canary fired" for canary in dict.fromkeys(_properties(case, CANARY))]
	verdict.problems += [
		f"{name}: reached its {budget} s timeout, whose failure a later one can hide"
		for budget in _properties(case, TIMEOUT)
	]
	if failure is not None:
		_classify_failure(case, failure, verdict)
	broken = error is not None or failure is not None
	if name.startswith(f"{OPERATION_TEST}["):
		verdict.operations += 1
		if broken:
			verdict.failed += 1
		elif case.find("skipped") is not None:
			verdict.skipped += 1
		else:
			verdict.passed += 1
	return broken


def classify(report: Path, *, pytest_exit_code: int) -> Verdict:
	verdict = Verdict()
	if pytest_exit_code >= 2:
		verdict.problems.append(
			f"pytest exited with {pytest_exit_code}: interrupted, internal error, usage error or nothing collected"
		)
	try:
		cases = list(ET.parse(report).getroot().iter("testcase"))
	except (OSError, ET.ParseError) as exc:
		verdict.problems.append(f"cannot read {report}: {exc}")
		return verdict

	broken = sum(_classify_case(case, verdict) for case in cases)
	if pytest_exit_code == 0 and broken:
		verdict.problems.append(f"pytest exit code 0 disagrees with {broken} failed or errored tests in the report")
	if pytest_exit_code == 1 and not broken:
		verdict.problems.append("pytest exit code 1 disagrees with a report that records no failure")
	if verdict.operations == 0:
		verdict.problems.append("pytest collected no operation to fuzz")
	if not any(case.get("name") == REGRESSION_TEST for case in cases):
		verdict.problems.append(f"{REGRESSION_TEST} is missing from the report")
	return verdict


def render_summary(verdict: Verdict) -> str:
	lines = [
		"### Deep fuzz",
		"",
		"| Operations | Passed | Failed | Skipped |",
		"|---:|---:|---:|---:|",
		f"| {verdict.operations} | {verdict.passed} | {verdict.failed} | {verdict.skipped} |",
		"",
	]
	if verdict.findings_by_check:
		lines += ["| Schemathesis check failure | Operations |", "|---|---:|"]
		lines += [f"| `{check}` | {count} |" for check, count in sorted(verdict.findings_by_check.items())]
		lines += ["", "<details><summary>Operations with findings</summary>", ""]
		lines += [
			f"- `{op}`: {', '.join(f'`{check}`' for check in checks)}"
			for op, checks in sorted(verdict.findings_by_operation.items())
		]
		lines += ["", "</details>", ""]
	if verdict.problems:
		lines += ["**The run is unsound.** These are not Schemathesis findings:", ""]
		lines += [f"{number}. {problem}" for number, problem in enumerate(verdict.problems, start=1)]
	else:
		lines.append("Every failure is a Schemathesis check failure; the `deep-fuzz-report` artifact has the details.")
	return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
	parser = argparse.ArgumentParser(description="Classify a deep fuzz JUnit report and summarise it in Markdown.")
	parser.add_argument("report", type=Path)
	parser.add_argument("--pytest-exit-code", type=int, required=True)
	args = parser.parse_args(argv)
	verdict = classify(args.report, pytest_exit_code=args.pytest_exit_code)
	sys.stdout.write(render_summary(verdict))
	return 1 if verdict.problems else 0


if __name__ == "__main__":
	raise SystemExit(main())
