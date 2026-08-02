#!/usr/bin/env python3
"""Refresh the FE's contract artifacts from the backend's OpenAPI schema.

Single source of truth is ``backend/openapi.json`` (kept honest by the backend
drift check, ``scripts/check_openapi_drift.py``). This script:

1. copies ``backend/openapi.json`` -> ``frontend/swagger/openapi.json``;
2. runs ``dart run build_runner build`` in ``frontend/``, which makes
   swagger_dart_code_generator emit the Dart models into
   ``frontend/lib/generated/``.

The generated models are committed. CI runs this script and fails on
``git diff --exit-code``, so a stale schema copy or stale generated models
cannot merge silently.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BACKEND_SPEC = REPO_ROOT / "backend" / "openapi.json"
FRONTEND_SPEC = REPO_ROOT / "frontend" / "swagger" / "openapi.json"
FRONTEND_DIR = REPO_ROOT / "frontend"


def _run(args: list[str]) -> int:
    # On Windows, `dart` resolves to dart.bat, which CreateProcess cannot
    # execute directly — route through the shell there, plain exec elsewhere.
    return subprocess.run(args, cwd=FRONTEND_DIR, shell=os.name == "nt").returncode


def main() -> int:
    shutil.copyfile(BACKEND_SPEC, FRONTEND_SPEC)
    build = _run(["dart", "run", "build_runner", "build"])
    if build != 0:
        return build
    # The generator's output is not always dart-format-clean; CI diffs the
    # committed artifacts, so the pipeline formats what it generates.
    return _run(["dart", "format", "lib/generated"])


if __name__ == "__main__":
    raise SystemExit(main())
