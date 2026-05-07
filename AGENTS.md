# AGENTS

## Engineering Guidelines

- Safety first. Prefer defensive programming, make invariants explicit, fail fast on programmer errors, and test invalid cases as well as valid ones.
- Prefer defensive programming. Validate assumptions, handle edge cases deliberately, and make failure modes explicit.
- Prefer composition over inheritance unless inheritance is clearly the simpler and more maintainable choice.
- Do not swallow errors. Either handle them meaningfully or propagate them with enough context to diagnose the failure.
- Put explicit limits on anything that can grow, stall, or retry forever. This includes timeouts, retry caps, queue bounds, payload limits, pagination limits, and similar operational bounds.
- Be liberal in what we accept as input, and strict in what we emit as output. Parse inputs generously where it improves compatibility, but keep our own outputs precise, validated, and predictable.
- Normalize external input at the boundary. After parsing generously where appropriate, convert immediately into a strict internal model with validated assumptions.
- Keep warnings, lints, and tests clean as part of correctness, not as optional polish.
- Apply these standards both when writing code and when reviewing code.

## Python Tooling

- Use `uv run` for Python commands so they execute with the project-managed environment and locked dependencies. For example: `uv run pytest` and `uv run ruff check`.
- For backend formatting, ALWAYS RUN `uv run ruff format .`. Never format individual files, just call format over the whole backend each time.
- For backend lint validation, prefer running `uv run ruff check .` from `backend` instead of per-file ruff checks. Do not use Ruff unsafe fixes unless explicitly requested.
- For the full backend test suite, run `uv run pytest` from `backend`.

## Commit Messages

- Use a concise imperative subject line that explains the change, not just the touched file.
- For non-trivial fixes, include a commit body that explains the root cause, the approach taken, and the user-visible or operational impact.
- Mention important validation in the body when tests, lint, migrations, or manual checks materially support the change.
- Keep unrelated changes out of the same commit. If a working tree is mixed, stage explicit paths and make the commit message match only those staged changes.

## Flutter From Codex/WSL

- This repo uses a Windows Flutter install mounted into WSL. Do not run `flutter ...` directly from the bash shell in Codex; it can fail with `shared.sh: line 5: $'\r': command not found`.
- From this environment, invoke Flutter through the Windows shell instead:
  - `cmd.exe /c flutter analyze`
  - `cmd.exe /c flutter test`
- If a Windows-shell Flutter command fails with `UtilBindVsockAnyPort:287: socket failed 1`, rerun it with escalated permissions from Codex.
- For local app runs, prefer the checked-in PowerShell helper from the repo root:
  - `powershell.exe -ExecutionPolicy Bypass -File frontend\\run-local-dev.ps1`
- `frontend/run-local-dev.ps1` already sets:
  - `ANDROID_ADB_SERVER_PORT=5067`
  - `--dart-define=API_URL=http://localhost:<BACKEND_PORT>/api/v1`
