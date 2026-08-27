# Repository Guidelines

Notif is a personal app that does what I want, which in this case and as of 2026-05-10 is collect updates and information from several sources and centralizes them in one place. Planned expansions (hosted agent for talking about content, X profile export and checking profiles for updates, F-Droid hosted for app updates).

This codebase optimizes for the long-term sober, lucid, maintainable, high quality code over short-term fake pragmatic speed. We are not in a rush. Boundaries are explicit, external data is treated as external data, and architectural invariants live in CI rather than in folklore.

## Project Structure & Module Organization

Notif is a Django backend plus Flutter frontend. Backend code lives in `backend/`, with settings in `backend/notif/` and apps such as `accounts/`, `monitoring/`, and `ops/`. Backend tests are colocated as `tests.py`, `test_*.py`, or app-level `tests/`; fixtures live under `backend/monitoring/tests/`. Frontend code lives in `frontend/lib/`, grouped into `screens/`, `services/`, and `commons/`; tests are in `frontend/test/`. Deployment files are at the root (`compose.yaml`, `Caddyfile`, `deploy.sh`) and in `deploy/`; notes belong in `docs/`.

## Build, Test, and Development Commands

### Backend tooling

All Python commands run under `uv run` so they pick up the locked environment. Run them from `backend/` unless noted.

- Format: `uv run ruff format .` — format the whole tree, even for single file edits
- Lint: `uv run ruff check .` — do not pass `--unsafe-fixes` unless explicitly requested
- Type-check: Run `uv run mypy .` always, even for single file edits
- Complexity gate: `uv run xenon . --max-absolute C --max-average A --max-average-num 3.0 --max-modules B --exclude "*/migrations/*"` — the same command CI runs
- Complexity report: `uv run radon cc . -s -n C -e "*/migrations/*"` for the offenders, `uv run radon cc . -a --total-average -e "*/migrations/*"` for the average, `uv run radon mi . -s -e "*/migrations/*"` for maintainability index
- Tests: `uv run pytest -q` for the full suite
- Migrations: if a model changes, run `uv run python manage.py makemigrations` and commit the migration. CI fails on missing migrations

The complexity thresholds are ceilings pinned at where the tree already sits, not aspirations: the gate is green today, and a change that pushes a block past grade C, a module past grade B, or the tree average past 3.0 fails CI. Note what that does *not* catch — a block can grow from CC 11 to CC 20 without leaving the C band, and the average has room to drift from 2.48 up to 3.0. The gate stops cliffs, not creep. Migrations are excluded because they are generated and frozen, matching the ruff and mypy excludes. Tighten the numbers as the offenders get refactored; never loosen them to land a change.

### Frontend tooling

Dart / Flutter commands run from `frontend/`.

- Format: `dart format .`
- Analyze: `flutter analyze --no-pub`
- Tests: `flutter test --no-pub` for the full suite. Architecture tests in `test/architecture_test.dart` run as part of this.
- Web build (smoke): `flutter build web --no-pub` after touching web-only code paths.

## Coding Style & Naming Conventions

Backend code targets Python 3.14 and Django 6. Ruff owns formatting with tabs and a 120-column line length; use `snake_case` for functions, `PascalCase` for classes, and typed shared boundaries. Frontend code follows `very_good_analysis`; use Dart `lowerCamelCase` for members and `UpperCamelCase` for types/widgets. Prefer composition, validate input at boundaries, do not swallow errors, and keep retries, payloads, timeouts, and pagination explicitly bounded.

- **Make impossible states impossible.** Auth is a sealed transition system, not nullable booleans. Persisted preferences are typed via `PreferenceStore`, not raw `SharedPreferences`. Failures are classified via `AppFailure` / `FailureCategory`, not raw exception strings.
- **Bounded everything.** Timeouts, retries, queues, payloads, pagination windows, log tails, GC ranges. If it can grow, stall, or retry forever, give it an explicit cap.
- **Composition over inheritance** unless inheritance is genuinely simpler. Mixins and abstract base classes exist; reach for them when the alternative is uglier, not because they look familiar.
- **Errors carry context.** Either handle them meaningfully or propagate with enough information to diagnose. Bare `except` / `catch` is reserved for platform or framework calls that can throw arbitrary objects, and gets a comment explaining why.
- **Tests, lints, type errors, and architecture checks are correctness, not polish.** Do not land code that defers them.

## Testing Guidelines

Backend tests use `pytest`, `pytest-django`, Hypothesis, and xdist. Name tests `test_*.py`, `*_test.py`, or use app test modules; mark slower fixtures with `slow`, `feed`, `e2e`, or `property`. Coverage has an 80% floor. Frontend tests use `flutter_test`; keep widget and service tests in `frontend/test/` with `_test.dart` names.

## Commit & Pull Request Guidelines

Use concise imperative commit subjects, for example `Harden refresh token sessions` or `Parse frontend service contracts`. For non-trivial changes, include a body explaining root cause, approach, and impact. Keep unrelated backend, frontend, deploy, and documentation changes separate when practical. Pull requests should describe behavior changes, list validation commands, link issues when relevant, and include screenshots for visible UI changes.

## Security & Configuration Tips

Do not commit secrets or production `.env` values. Treat live deployment behavior as distinct from repo defaults; verify Caddy, Docker, and VPS state directly before changing production-sensitive configuration. Do not rewrite deployed migration history; add new migrations for new deltas.
