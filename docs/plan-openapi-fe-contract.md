# Plan: OpenAPI schema → FE contract, plus response-conformance trial

Status: **draft, awaiting approval** · Date: 2026-08-02

## Why

The frontend and backend are built against the same API, but nothing connects the
two halves. The backend guarantees `backend/openapi.json` matches its code
(`scripts/check_openapi_drift.py` runs in CI); the frontend parses responses by
hand with zero reference to that schema. The merge of `deploy-config` into master
surfaced the exact bug class this creates: both halves shipped *different*
Strategy contracts (the backend gained `user`/`data`; the FE was written against
the older shape) and every test passed, because FE tests mock the API and
drift-check cannot see rendered bytes.

Goal: make the schema the FE's compile-time source of truth, and prove the wire
bytes match the schema with a single trial test.

## Decisions (made, with why)

- **Generated types only, not a full client.** The FE already has the right
  facade — `data.dart` / `auth.dart` / `ops.dart` / `failures.dart` / the
  dio-based `api_client.dart` with interceptors. A generated client would fight
  the hand-rolled error classification, envelopes, and pagination shapes, and
  add churn for ~10% more safety. Types give ~90% of the value at ~40% of the
  churn.
- **`swagger_dart_code_generator`, not `openapi-generator`.** Dart-native
  (`build_runner`, no JVM in CI), readable annotated output, passes
  `very_good_analysis`. `openapi-generator`'s Dart output is the dated
  "Dart 1.x" client style, and its strengths (multi-language, huge config) are
  irrelevant here. No docker/Java needed.
- **Feed the generator a components-only schema (paths stripped).**
  `swagger_dart_code_generator` emits models *and* dio-based API classes
  together by default. The architecture test (`frontend/test/architecture_test.dart`)
  bans `package:dio` outside `api_client`/`auth`/`data`/`failures`. Stripping
  `paths` makes it emit models only — dio-free, architecture-test-clean. The
  strip script is a small repo-owned Python tool, next to
  `scripts/check_openapi_drift.py`.
- **Generated code is committed** so FE builds/CI never need codegen to run.
  CI regenerates and fails on diff (mirrors the backend drift check).
- **Adoption starts with `Strategy`/`Link` in `data.dart`** — the exact models
  that caused the merge pain — and extends to the rest in a follow-up.
- **One response-conformance trial test with `openapi-core`** (backend dev
  dep), not schemathesis — lighter for a single trial. If it proves valuable,
  scale from there.
- **Prod runs SQLite** (`SQLITE_PATH=/app/data/db.sqlite3` in `compose.yaml`
  and `.env.production.example`). No Postgres test infrastructure needed; the
  existing SQLite-based test suite is prod-representative.

## Constraints discovered

- `frontend/test/architecture_test.dart` bans `package:dio` outside
  `api_client`/`auth`/`data`/`failures` and bans `Dio(` construction anywhere
  else → generated API classes would violate it; hence models-only.
- `backend/scripts/check_openapi_drift.py` already regenerates `openapi.json`
  (`--write`) and is enforced in `backend.yml` CI (`OpenAPI schema drift` step).
- `frontend.yml` CI has no contract step today; it gains one.
- `frontend/pubspec.yaml` has no `build_runner`/codegen deps yet.
- `NOTES.md` ("API error format unification") already plans FE client
  generation from `openapi.json` and flags the `trigger_scrape` envelope
  dialect — the conformance trial also guards that envelope.

## Phases

### 1. Codegen pipeline (worktree `impl/openapi-fe-contract`)

- Fetch latest master; `git worktree add .claude/worktrees/openapi-fe-contract
  -b impl/openapi-fe-contract origin/master`
- Add `swagger_dart_code_generator` + `build_runner` to `frontend/pubspec.yaml`
  dev deps; add `build.yaml` with `input_folder: ../backend` (openapi.json is
  committed there) and output to `lib/generated/`
- Add `backend/scripts/emit_models_schema.py`: read `openapi.json`, strip
  `paths`, write a components-only schema the FE generator consumes
- First `dart run build_runner build` → generated models into
  `frontend/lib/generated/` with a DO NOT EDIT header; commit the output
- Verify `flutter analyze` passes, including the dio-boundary architecture test

### 2. Contract freshness guard (CI)

- `frontend.yml`: add a step that regenerates the models and fails on
  `git diff --exit-code` (mirror of the backend drift step)
- Confirm backend CI's existing drift step keeps `openapi.json` honest
  (already runs `check_openapi_drift.py`)

### 3. Adopt generated types in the FE

- In `data.dart`, replace hand-rolled parsing for `Strategy`/`Link` with the
  generated types; `api_client.dart` and the service layer stay as-is
- `flutter analyze` + full `flutter test` green
- Follow-up (separate): extend to the remaining models (`SystemEvent`,
  `CaddyLogEntry`, notifications, …) and consider a raw-cast architecture rule
  once hand-rolled parsing is contained

### 4. Response-conformance trial (one test)

- Add `openapi-core` to backend dev dependencies
- One `live_server` test: register → login over real HTTP → `GET
  /api/v1/monitoring/strategies/`, validate the response bytes against
  `openapi.json` via `openapi_core`
- Expected to exercise the Strategy `user`/`data` contract that the merge
  surfaced; that is the proof-of-value

### 5. Validation and PR

- Full backend chain in the worktree: `uv lock --check`, ruff format/check,
  mypy, `manage.py check`, `makemigrations --check`, drift check, pytest
- Full frontend chain: `dart format`, `flutter analyze`, `flutter test`,
  `flutter build web --no-pub`
- Push `impl/openapi-fe-contract`; open one PR against master (codegen +
  adoption + conformance trial together; split if review prefers)

## Related / in flight

- PRs #75–#80 (deploy-systemd, ssrf-guard, owner-scoping, client-telemetry,
  security-audit, chore-cleanups) are open against master; another agent is
  updating them. This plan is independent of them — the codegen work cuts from
  whatever master is current when it starts.
- `deploy-config` branch holds the merged unique work; close once #75–#80 land.

## Validation checklist

```bash
# backend (from worktree backend/)
uv lock --check
uv run ruff format --check .
uv run ruff check .
uv run mypy .
uv run python manage.py check
uv run python manage.py makemigrations --check --dry-run
uv run python scripts/check_openapi_drift.py
uv run pytest -q --basetemp="$TEMP/pytest-openapi-fe"

# frontend (from worktree frontend/)
dart format --set-exit-if-changed .
flutter analyze --no-pub
flutter test --no-pub
flutter build web --no-pub
```
