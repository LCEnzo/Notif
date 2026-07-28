from __future__ import annotations

import argparse
import difflib
import subprocess
import sys
import tempfile
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
SCHEMA_PATH = BACKEND_ROOT / "openapi.json"


def generate_schema(output_path: Path) -> None:
	subprocess.run(
		[
			sys.executable,
			"manage.py",
			"spectacular",
			"--format",
			"openapi-json",
			"--file",
			str(output_path),
			"--validate",
			# --validate alone only catches structurally invalid OpenAPI. The failures
			# that actually reach clients are drf-spectacular's *warnings* — e.g.
			# "could not resolve ... defaulting to generic free-form object", which is
			# how an endpoint returning an array shipped a schema saying object.
			"--fail-on-warn",
		],
		cwd=BACKEND_ROOT,
		check=True,
	)


def check_schema() -> int:
	with tempfile.TemporaryDirectory() as temp_dir:
		generated_path = Path(temp_dir) / "openapi.json"
		generate_schema(generated_path)

		committed_text = SCHEMA_PATH.read_text(encoding="utf-8")
		generated_text = generated_path.read_text(encoding="utf-8")

	if committed_text.rstrip("\n") == generated_text.rstrip("\n"):
		return 0

	sys.stdout.writelines(
		difflib.unified_diff(
			committed_text.splitlines(keepends=True),
			generated_text.splitlines(keepends=True),
			fromfile="openapi.json",
			tofile="generated openapi.json",
		)
	)
	sys.stderr.write(
		"OpenAPI schema drift detected. Run `uv run python scripts/check_openapi_drift.py --write` from backend/.\n"
	)
	return 1


def main() -> int:
	parser = argparse.ArgumentParser(description="Check committed OpenAPI schema for drift.")
	parser.add_argument(
		"--write",
		action="store_true",
		help="Regenerate backend/openapi.json instead of only checking for drift.",
	)
	args = parser.parse_args()

	if args.write:
		generate_schema(SCHEMA_PATH)
		return 0

	return check_schema()


if __name__ == "__main__":
	raise SystemExit(main())
