# Review rules

What a reviewer of a Notif change reports, and how. AGENTS.md stays the source of the project's invariants;
this file narrows them to findings. Applies to local `/code-review` runs and to the CI reviewer
(`.github/workflows/claude-review.yml`), which reads this file from the PR's base branch, so a change to it
takes effect once merged.

## What failure looks like in Notif

Report a change that:

1. Leaves something unbounded: a timeout, retry, queue, payload, pagination window, log tail or GC range
   that can grow, stall or retry forever.
2. Trusts external data: feed, scrape, HTTP, user or file input used without validation at the boundary.
3. Loses error context: a swallowed error, a bare `except`/`catch` without the comment that justifies it,
   or a raw exception string where `AppFailure` / `FailureCategory` belongs.
4. Admits an impossible state: nullable booleans where a sealed type belongs (auth above all), or raw
   `SharedPreferences` where `PreferenceStore` belongs.
5. Endangers data or deployment: deletes or rewrites data without a guard, rewrites deployed migration
   history, or changes a model without a migration.
6. Exposes a secret: credentials, tokens or production `.env` values in code, logs, errors or fixtures.
7. Ships a test that would still pass if the change were wrong.
8. Is plainly wrong: logic, types, concurrency, an off-by-one, a broken API contract.

## Severity tags

| Tag | Meaning |
|---|---|
| `[Important]` | Breaks behavior, loses or leaks data, weakens auth, or violates an invariant above. Fix before merge. |
| `[Nit]` | Real but minor. At most 3 per review; drop the rest. |
| `[Pre-existing]` | A real bug in code the diff shows, which the change did not introduce. |

## Risk tiers

The summary names the highest tier a changed path falls into, and the paths that set it.

| Tier | What it covers |
|---|---|
| high | `backend/accounts/`, auth code anywhere, secrets handling, `.github/workflows/`, `deploy.sh`, `deploy/`, `compose.yaml`, `Caddyfile`, any `migrations/` directory, anything that deletes data, F-Droid signing |
| low | Docs or comments only |
| medium | Everything else |

## Do not report

1. What CI already enforces: formatting, ruff, mypy, `flutter analyze`, the OpenAPI drift check.
2. Generated, locked or captured files: `backend/openapi.json`, `frontend/lib/generated/`, `backend/uv.lock`,
   `frontend/pubspec.lock`, `.secrets.baseline`, and the captured pages under `backend/monitoring/tests/`
   (`*.xml`, `*.html`). Review the code that produces or consumes them instead.
3. Style, naming or refactoring preferences that break none of the rules above.

## Evidence

Every finding sits on a line on the new side of the reviewed diff, cites `path:line`, and names its bug
class, for example "unbounded retry" or "unvalidated external input". A claim about code outside the diff
needs its own `path:line` in the finding's text. No citation, no finding.

## Summary

Count first. The first line is `Round N: M findings (I important, K nits, P pre-existing)`, or
`Round N: nothing to fix`; a local review without rounds leaves out `Round N: `. The second line is
`Risk: <tier> (<paths that set it>)`. Then one line per finding.

From round 3 on, the third line reads: `Round cap reached: step back and reconsider the approach before
another fix round.`

In CI, `.github/scripts/claude-review.sh` writes this summary from the reviewer's findings. It enforces the
nit cap, drops findings outside the reviewed diff and repeats of earlier ones, raises the tier to high for
the paths listed above, and ends with `Reviewed-SHA: <head sha>`. The next round reviews from that commit.
