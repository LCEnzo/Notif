"""Tell a deep fuzz run's expected findings from a broken run, and summarise the run in Markdown.

Reads the JUnit XML that ``pytest test_api_fuzz.py --junitxml`` writes. Exits 0 when every failure is
a Schemathesis check failure, 1 when the run itself is unsound. Rules and sources: docs/testing.md.
"""

from __future__ import annotations

import argparse
import itertools
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

OPERATION_TEST = "test_operation_survives_generated_input"
REGRESSION_TEST = "test_live_server_shares_the_test_database_connection"
# Assertion messages in test_api_fuzz.py: either one means generated requests miss the handler.
CANARIES = {
	"credential canary": "fuzzer credential was rejected",
	"CSRF canary": "fuzzer CSRF token was rejected",
}
FAILURE_GROUP = "schemathesis.core.failures.FailureGroup"
UNLISTED = "(not listed in the report)"
_MAX_DETAIL = 300

# CPython's exception group layout (traceback._ExceptionPrintContext): the top group's lines carry a
# "  | " margin, its children's "    | ", and a separator line opens each child.
_TOP_GROUP_START = "+ Exception Group Traceback (most recent call last):"
_TOP_HEADLINE = re.compile(r"^  \| (?P<type>[A-Za-z_][\w.]*)(?::|$)")
_CHILD_SEPARATOR = re.compile(r"^  (?:\+-|  )\+-{16} (?:\d+|\.\.\.) -{16}$")
_CHILD_LINE = re.compile(r"^    \| (?P<content>.*)$")
_CHECK_FAILURE = re.compile(r"^schemathesis\.[\w.]*\.(?P<name>\w+): (?P<title>.+)$")
_ELIDED = re.compile(r"^and \d+ more exceptions?$")


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


def _canary(text: str) -> str | None:
	return next((name for name, phrase in CANARIES.items() if phrase in text), None)


def _check_failures(text: str) -> list[str] | None:
	"""The check failures in a failure whose top-level exception is a FailureGroup; None for anything else.

	Schemathesis raises a FailureGroup of check failures, each stripped of its traceback, and
	Hypothesis never wraps one: see docs/testing.md.
	"""
	lines = text.strip().splitlines()
	if not lines or lines[0] != _TOP_GROUP_START:
		return None
	headline = next((match for line in lines[1:] if (match := _TOP_HEADLINE.match(line))), None)
	if headline is None or headline["type"] != FAILURE_GROUP:
		return None
	checks: list[str] = []
	for separator, child in itertools.pairwise(lines):
		if not _CHILD_SEPARATOR.match(separator):
			continue
		content = match["content"] if (match := _CHILD_LINE.match(child)) else ""
		if failure := _CHECK_FAILURE.match(content):
			checks.append(f"{failure['title']} (`{failure['name']}`)")
		elif _ELIDED.match(content):
			checks.append(UNLISTED)
		else:
			return None
	return checks or None


def _classify_case(case: ET.Element, verdict: Verdict) -> bool:
	"""Record one test case; True when it failed or errored."""
	name = case.get("name", "")
	is_operation = name.startswith(f"{OPERATION_TEST}[")
	error, failure = case.find("error"), case.find("failure")
	if error is not None:
		verdict.problems.append(f"{name}: {_first_line(error.get('message', 'error'))}")
	if failure is not None:
		message, text = failure.get("message", ""), failure.text or ""
		checks = _check_failures(text) if is_operation else None
		if name == REGRESSION_TEST:
			verdict.problems.append(f"{REGRESSION_TEST} failed: {_first_line(message)}")
		elif canary := _canary(f"{message}\n{text}"):
			verdict.problems.append(f"{name}: the {canary} fired: {_first_line(message)}")
		elif checks is not None:
			verdict.findings_by_operation[name.removeprefix(f"{OPERATION_TEST}[").removesuffix("]")] = checks
			verdict.findings_by_check.update(set(checks))
		else:
			verdict.problems.append(f"{name}: not a Schemathesis check failure: {_first_line(message)}")
	broken = error is not None or failure is not None
	if is_operation:
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
		lines += [f"| {check} | {count} |" for check, count in sorted(verdict.findings_by_check.items())]
		lines += ["", "<details><summary>Operations with findings</summary>", ""]
		lines += [f"- `{op}`: {', '.join(checks)}" for op, checks in sorted(verdict.findings_by_operation.items())]
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
