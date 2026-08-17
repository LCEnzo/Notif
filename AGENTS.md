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
- Tests: `uv run pytest -q` for the full suite
- Migrations: if a model changes, run `uv run python manage.py makemigrations` and commit the migration. CI fails on missing migrations

### Frontend tooling

Dart / Flutter commands run from `frontend/`.

- Format: `dart format .`
- Analyze: `flutter analyze --no-pub`
- Tests: `flutter test --no-pub` for the full suite. Architecture tests in `test/architecture_test.dart` run as part of this.
- Web build (smoke): `flutter build web --no-pub` after touching web-only code paths.

## Worktrees & Scratch Space

Everything this repo generates stays inside this repo. Nothing is written to `C:\tmp\`, `%TEMP%`, `/tmp`, the home directory, or any sibling folder.

- **Worktrees live in `.claude/worktrees/<name>/`.** Create them with `git worktree add .claude/worktrees/<name> -b <branch> origin/master`. Never target a path outside the repository root.
- **Scratch and temporary output lives in `.claude/tmp/`.** This includes pytest's `--basetemp`, generated reports, downloaded fixtures, one-off scripts, and any other working file that is not a deliverable. Create the directory on demand.
- **`.claude/` is gitignored**, so neither worktrees nor scratch files can reach a commit. That is the point: the isolation is structural, not a habit anyone has to remember.
- **Clean up when the branch is done:** `git worktree remove .claude/worktrees/<name> --force` (`--force` because `.venv`, `.env`, and the SQLite file are untracked), then `git branch -D <branch>` if abandoned.

The rule exists because out-of-tree worktrees rot silently. They keep gitignored secrets (`backend/.env`) and multi-hundred-megabyte virtualenvs alive long after their branch has merged, they are invisible to every cleanup path that walks the repo, and nothing about the repository's own state hints that they exist. Keeping them under `.claude/` makes `git worktree list` the complete inventory.

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
