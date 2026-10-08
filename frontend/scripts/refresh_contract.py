#!/usr/bin/env python3
"""Refresh the FE's contract artifacts from the backend's OpenAPI schema.

Single source of truth is ``backend/openapi.json`` (kept honest by the backend
drift check, ``scripts/check_openapi_drift.py``). This script:

1. clears build_runner's cache (``frontend/.dart_tool/build``) when the schema
   or ``frontend/lib/generated/`` changed since its last successful run (see
   the README's OpenAPI section for why);
2. copies ``backend/openapi.json`` -> ``frontend/swagger/openapi.json``
   (gitignored; build_runner only reads inputs inside the package);
3. runs ``dart run build_runner build`` in ``frontend/``, which makes
   swagger_dart_code_generator emit the Dart models into
   ``frontend/lib/generated/``, then formats them;
4. on success, records what it generated in ``frontend/.dart_tool/``.

The generated models are committed. CI runs this script and fails on
``git diff --exit-code``, so stale generated models cannot merge silently.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BACKEND_SPEC = REPO_ROOT / "backend" / "openapi.json"
FRONTEND_SPEC = REPO_ROOT / "frontend" / "swagger" / "openapi.json"
FRONTEND_DIR = REPO_ROOT / "frontend"
GENERATED_DIR = FRONTEND_DIR / "lib" / "generated"
BUILD_CACHE = FRONTEND_DIR / ".dart_tool" / "build"
STAMP = FRONTEND_DIR / ".dart_tool" / "notif_contract.stamp"


def _run(args: list[str]) -> int:
    # On Windows, `dart` resolves to dart.bat, which CreateProcess cannot
    # execute directly — route through the shell there, plain exec elsewhere.
    return subprocess.run(args, cwd=FRONTEND_DIR, shell=os.name == "nt").returncode


def _models_digest() -> str:
    outer = hashlib.sha256()
    for path in sorted(p for p in GENERATED_DIR.rglob("*") if p.is_file()):
        name = path.relative_to(GENERATED_DIR).as_posix()
        outer.update(f"{name}\0{hashlib.sha256(path.read_bytes()).hexdigest()}\n".encode())
    return outer.hexdigest()


def _read_stamp() -> dict[str, str]:
    try:
        lines = STAMP.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return {}
    return {key: value for key, _, value in (line.partition(" ") for line in lines)}


def _stale_reason(schema: str, models: str) -> str | None:
    stamp = _read_stamp()
    if not stamp:
        return "no record of a previous successful refresh"
    if stamp.get("schema") != schema:
        return "backend/openapi.json changed since the last successful refresh"
    if stamp.get("models") != models:
        return "lib/generated/ changed since the last successful refresh"
    return None


def main() -> int:
    schema_bytes = BACKEND_SPEC.read_bytes()
    schema = hashlib.sha256(schema_bytes).hexdigest()
    reason = _stale_reason(schema, _models_digest())
    if reason is not None and BUILD_CACHE.exists():
        shutil.rmtree(BUILD_CACHE)
        print(f"refresh_contract: cleared frontend/.dart_tool/build: {reason}", flush=True)
    # Nothing under swagger/ is tracked, so a fresh checkout lacks the dir.
    FRONTEND_SPEC.parent.mkdir(exist_ok=True)
    # Copy the bytes that were hashed, so the stamp names exactly what the generator read.
    FRONTEND_SPEC.write_bytes(schema_bytes)
    build = _run(["dart", "run", "build_runner", "build"])
    if build != 0:
        return build
    # The generator's output is not always dart-format-clean; CI diffs the
    # committed artifacts, so the pipeline formats what it generates.
    fmt = _run(["dart", "format", "lib/generated"])
    if fmt != 0:
        return fmt
    STAMP.write_text(f"schema {schema}\nmodels {_models_digest()}\n", encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
