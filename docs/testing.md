# Backend test tooling

Why the backend's property tests, schema fuzzing and mutation testing are built the way they are. Code comments in these files point here instead of carrying the explanation:

| File | Topic |
|---|---|
| `backend/monitoring/tests.py` | Hypothesis property tests under mutmut |
| `backend/conftest.py` | `live_server` start order |
| `backend/test_api_fuzz.py` | Schemathesis fuzzing |
| `backend/pyproject.toml`, `[tool.mutmut]` | Mutation testing |
| `.github/workflows/deep-sweeps.yml` | Scheduled deep fuzz and mutation runs |
| `.github/scripts/deep-sweeps-gate.sh` | Which sweeps a scheduled run starts |

Source references below are to the locked versions: Hypothesis 6.168.1, Schemathesis 4.24.3, mutmut 3.7.0, pytest 9.1.1, pytest-django 4.14.0. Timings are dated measurements, not guarantees.

## Hypothesis tests are plain functions

`@given` tests are module-level functions, not `TestCase` methods, so that they survive mutmut.

The `@given` wrapper keeps, per thread, the `self` of its first call (`thread_local.prev_self` in `hypothesis/core.py`) and fails `HealthCheck.differing_executors` when a later call brings a different object. pytest builds a new `TestCase` instance for each test item on every run (`TestCaseFunction._getinstance` in `_pytest/unittest.py`), but imports test modules with `importlib.import_module`, which returns the module already in `sys.modules`. A second `pytest.main()` in the same process therefore reuses the wrapper, memory included, and hands it a new `self`.

`mutmut run` (`_run` in `mutmut/__main__.py`) calls `pytest.main()` repeatedly in one process and then in forks of it:

1. A coverage run for `mutate_only_covered_lines`. Afterwards mutmut unloads the modules that run imported (`gather_coverage` in `mutmut/code_coverage.py`).
2. A stats run that maps tests to the functions they reach, or a collect-only listing when stats are cached.
3. A clean run of the covering tests, then a forced-fail run.
4. One `os.fork()` per mutant. The child calls `pytest.main()` again in the inherited interpreter, wrapper state included.

A `@given` method on a `TestCase` fails the health check on every run after the first one that calls it, which breaks the baseline or reports mutants as killed. Neither property test touches the database (pytest-django refuses database access without a `django_db` mark), so a Django `TestCase` added nothing.

### Timing checks off on the feed dedup property

`test_feed_strategy_dedup_is_idempotent` sets `deadline=None` and suppresses `HealthCheck.too_slow`. It tests a dedup invariant, not speed.

Hypothesis fails `too_slow` when the total draw time of the first valid examples exceeds `max(1 s, 5 × deadline)` (`hypothesis/internal/conjecture/engine.py`): 1 s at the default 200 ms deadline, 30 s with `deadline=None`. On the first draw that needs them, Hypothesis harvests constants from local source modules and caches them under `.hypothesis/constants/` relative to the working directory (`_get_local_constants` in `hypothesis/internal/conjecture/providers.py`, `hypothesis/internal/constants_ast.py`). mutmut runs pytest from a fresh `mutants/` tree with no such cache, and there the first draw took a second or more.

## `live_server` starts after the test database

`backend/conftest.py` overrides pytest-django's session-scoped `live_server` so it depends on `django_db_setup`.

pytest-django hands the server thread the test's own connection only for SQLite databases that are in memory when `LiveServer` is constructed (`pytest_django/live_server_helper.py`). A test that requests `live_server` directly creates that session fixture before the function-scoped `transactional_db` sets up the test database. The server then starts against the file-backed `NAME` and shares nothing. Each request thread opens its own in-memory connection, which Django's SQLite backend never closes (`DatabaseWrapper.close` ignores in-memory databases), and the thread's exit leaves it to the garbage collector as a `ResourceWarning`, which the suite's `filterwarnings = error` turns into a failure.

`test_live_server_shares_the_test_database_connection` in `test_api_fuzz.py` pins the fix. Commit 614ad54 has the full trace.

## Schema fuzzing (`test_api_fuzz.py`)

`test_openapi_conformance.py` proves one hand-written round trip matches the schema. `test_api_fuzz.py` covers every operation in the committed `openapi.json` except `UNFUZZABLE_OPERATIONS`: Schemathesis generates inputs from each operation's parameter and body schemas, calls the live server, and checks the response.

### Profiles

`NOTIF_FUZZ_PROFILE` selects one. Any other value fails at import.

| | `ci` (default) | `deep` |
|---|---|---|
| Runs in | `backend.yml`, with the rest of the suite | `deep-sweeps.yml`, or by hand |
| Schemathesis checks | `not_a_server_error` only | every default check except `negative_data_rejection` |
| Phases | `fuzzing` | `examples`, `coverage`, `fuzzing` |
| `fuzzing` examples per operation | 5 | 200 |
| Per-test timeout | 120 s | 1800 s |
| Seed | fixed (`0`) | fresh per run |

`NOTIF_FUZZ_MAX_EXAMPLES` overrides the example count. The deep profile is expected to report findings, which is why it never gates a merge. By hand, from `backend/`:

    NOTIF_FUZZ_PROFILE=deep uv run pytest -q test_api_fuzz.py

Both per-test timeouts replace `addopts`' `--timeout=30`, which the `coverage` phase alone can exceed on the largest operations.

### Checks

`ci` keeps only `not_a_server_error`. On an API that was not written schema-first it has the best signal-to-noise ratio: a 500 is unambiguously a bug, whereas an undocumented 400 is usually a docs gap.

`deep` passes `checks=None`, which runs every registered check that the Schemathesis config enables, and the config enables all of them by default (`CheckContext` in `schemathesis/checks.py`): status code, content type, headers, response schema conformance, auth enforcement (`ignored_auth`) and others. It excludes `negative_data_rejection`, which requires a rejection status (400, 422 or one of a few other 4xx codes) for every schema-violating request. DRF is lenient by design: it ignores unknown query parameters and read-only fields (`Serializer._writable_fields`), and `CharField` coerces numbers to strings (`"name": 0` saves as `"0"`). Against this API the check reported that leniency on several write and list operations, burying the findings that matter.

The test adds two assertions of its own, in both profiles. `ci` fails only on a 5xx, so a fuzzer stuck at the auth layer would pass green while exercising nothing behind it. A valid session never earns a 401 on an operation that requires auth, and a CSRF token pair that lands never earns `403 CSRF Failed`. Either response means generated requests are not reaching the handler, and fails the test.

### Phases

Phase selection decides the runtime far more than `max_examples` does. `fuzzing` samples up to `max_examples` inputs. `examples` and `coverage` are attached to the test as explicit `@example`s (`schemathesis/generation/hypothesis/builder.py`), so `coverage` enumerates schema edge cases (missing required fields, wrong types, boundary values) whatever `max_examples` says. Adding `coverage` to `ci` took the module from ~35 s to ~3 min (Windows, `-n 4`, 2026-10-05), so `ci` samples and `deep` enumerates.

Hypothesis runs all explicit examples first and raises their failures before it starts generating (`hypothesis/core.py`). An operation with an `examples` or `coverage` finding therefore never reaches `fuzzing` in that run.

`stateful` is not listed because `schema.parametrize()` never runs it: the pytest integration maps only `examples`, `coverage` and `fuzzing` to test modes (`schemathesis/pytest/lazy.py`), and stateful testing needs `schema.as_state_machine()`. Listing it would only claim coverage.

### Seeding

`ci` is a merge gate, so it replays the same inputs on every run: a red gate points at the diff under review rather than at a newly sampled input. Exploring is `deep`'s job, so it keeps a fresh seed per run. The `ci` inputs still move when an operation's schema or the Hypothesis or Schemathesis version changes, and those changes arrive in a diff too.

Schemathesis seeds every test itself. Its config draws a random 128-bit seed when none is set (`schemathesis/config/__init__.py`) and applies it with `hypothesis.seed()` (`schemathesis/generation/hypothesis/builder.py`). Hypothesis checks an explicit seed before `derandomize` (`get_random_for_wrapped_test` in `hypothesis/core.py`), so `derandomize=True` would pin nothing here; `schema.config.seed = 0` does.

Replay is exact only with `PYTHONHASHSEED` pinned: for a few operations the inputs also depend on Python's per-process hash seed. This was observed, not traced to a mechanism.

### Credentials

`fuzz_credentials` creates the fuzzing user and logs it in over cookie transport, once per operation: a function-scoped fixture is set up once per test item, not once per generated example. The session and CSRF tokens go to `call_and_validate` as `cookies=` and `headers=` arguments, not through a `requests.Session` cookie jar, because Schemathesis treats only a credential it was handed explicitly as the real one:

1. The requests transport merges explicit `cookies` over the generated ones and records them on the response's `_override` (`schemathesis/transport/requests.py`).
2. `ignored_auth` (`schemathesis/specs/openapi/checks.py`) counts a credential found in `_override` as explicit. One it cannot trace there, such as a cookie from a session jar, counts as generated, and a 2xx carrying a generated credential is reported as ignored auth.
3. For an explicit credential, `ignored_auth` replays the request with exactly that credential stripped from the transport arguments (`build_retry_transport_kwargs` in `schemathesis/specs/openapi/_auth_retry.py`) and expects a 401.

By default Schemathesis also treats the schema's security schemes as parameters and generates a value for each (`with_security_parameters`, default true): a random `notif_session` cookie and a random `Authorization` header. The explicit cookie replaces a generated cookie of the same name. A generated header that starts with `Session` outranks any cookie, though, because `SessionTokenAuthentication.authenticate` tries the header first, and a dead header token earns a 401. Random credentials only exercise the rejection path anyway, so the test turns their generation off.

### Excluded operations

Every entry in `UNFUZZABLE_OPERATIONS` is API surface that nothing fuzzes, so the set stays small and each reason concrete.

| Operation | Why it is excluded | Why its neighbours are not |
|---|---|---|
| `auth_logout_create` | Revokes the session the fuzzer authenticates with, so every later call in the same test would 401 for the wrong reason. | `auth_sessions_revoke_all_create` spares the caller's own session. |
| `accounts_users_destroy` | A generated id can be the fuzzer's own, and deleting that user turns every later call into a 401. | `change_password` needs the current password, and `accounts_users_partial_update` refuses a password outright, so neither can lock the fuzzer out. |

### `format: uri` strings

The default strategy, hypothesis-jsonschema's, is `https://` plus a generated domain name (`STRING_FORMATS` in `hypothesis_jsonschema/_from_schema.py`), never an IP literal or a loopback name. `_FUZZ_URI` mixes public names with loopback, link-local and private addresses, so the link validator's non-public-host rejection runs too. That check reads the URL alone (`safe_fetch.reject_non_public_literal`), so it runs for real even though `conftest.py` stubs out DNS resolution. The strategy is also cheaper than the default: the deep profile collected in ~40 s with it and ~66 s without (Windows, 2026-10-05).

### Per-test state across examples

`live_server` is session-scoped, but the transactional database and the login session are per test, and Hypothesis cannot reset them between examples. State therefore accumulates within one operation's run. That is acceptable here: each example is an independent request, and the transactional test flushes the database between operations. Hypothesis fails `HealthCheck.function_scoped_fixture` unless it is suppressed.

### `localhost` resolves to IPv4 only

`ipv4_localhost` is purely a speed fix. The live server binds 127.0.0.1 (Django's `WSGIServer` uses IPv4 unless asked for IPv6) and Schemathesis opens a new `requests.Session`, and so a fresh connection, per request. On Windows every such connect tried `::1` first and stalled ~2 s on the refusal: single-process, the module took ~375 s without the fixture and ~30 s with it (2026-10-05).

## Mutation testing (mutmut)

Configured in `[tool.mutmut]` in `backend/pyproject.toml`. It is deliberately outside the merge path: nothing runs it in `backend.yml`, because a run costs hours and its result is a score to read, not a gate to pass. It runs from `deep-sweeps.yml`, on a schedule at most fortnightly and only when enough has changed, or by hand from `backend/`:

    uv run --group mutation mutmut run
    uv run --group mutation mutmut results

mutmut rewrites the sources into `backend/mutants/` and runs pytest there. It forks per mutant and exits on native Windows (`mutmut/__main__.py` checks `platform.system()` at import), so run it under WSL or Linux.

### `notif/config.py` is not mutated

mutmut skips decorated functions other than a lone `@staticmethod` or `@classmethod` (`mutmut/mutation/file_mutation.py`). Both functions in `config.py` are decorated (`@model_validator`, `@property`), so it yields no mutants today; the `do_not_mutate` entry keeps any later helper out too. `notif/test_config.py` covers its validation.

### pytest arguments

`pytest_add_cli_args` applies to every test run mutmut starts.

| Argument | Why |
|---|---|
| `-n 0` | Overrides `addopts`' four xdist workers. mutmut maps tests to the functions they reach by recording trampoline hits in its own process (`record_trampoline_hit` in `mutmut/__main__.py`), so the tests must run there. It already runs mutants in parallel, one fork each. |
| `-p no:randomly` | Repeats what mutmut already passes to its test runs (`PytestRunner._pytest_args_regular_run`). |
| `--no-cov` | Keeps pytest-cov out; mutmut gathers the line coverage it needs itself (`gather_coverage`). |
| `--hypothesis-seed=0` | Hypothesis seeds itself from OS entropy on every run, independently of pytest-randomly, so a property test could kill a mutant on one run and miss it on the next. A forced seed also leaves the example database out of the verdict: `run_engine` in `hypothesis/core.py` uses no database key when one is set. |

### The oracle

`pytest_add_cli_args_test_selection` makes the oracle the fast unit suite. mutmut reruns every test that reaches a mutated function, and the live-server tests (conformance, fuzz) reach most of the API layer at a second or more per test. `slow` and `e2e` tests parse real downloaded fixtures. The price: `e2e` is the most direct check on the parsers, so parser mutants it would kill can survive here.

The live-server modules are left out with `--ignore`, not `-m "not conformance and not fuzz"`. pytest imports a module before it evaluates that module's markers, and both modules build their OpenAPI schema at import time. Under mutmut the conformance module's import fails (PyYAML cannot load openapi-spec-validator's meta-schema), which fails the baseline run; `--ignore` prevents collection outright.

`ops/tests.py::OpsApiTestCase::test_openapi_schema_generates` is deselected because under mutmut it fails even with no mutant active: PyYAML cannot emit the schema drf-spectacular builds. A fresh pytest process over the same `mutants/` tree passes it, so the trigger appears to be mutmut's repeated in-process runs, not the rewritten sources. Neither PyYAML failure has been traced to a cause.

### Files copied into `mutants/`

mutmut copies `source_paths` plus `also_copy` into `mutants/` and runs there. Its own defaults (`tests/`, `test/`, `test*.py` and the lock and config files, in `mutmut/configuration.py`) leave out `conftest.py`, whose autouse resolver stub keeps the suite off real DNS. Without it, tests that reach the guarded transport would resolve hosts for real.

## Deep sweeps workflow

`.github/workflows/deep-sweeps.yml` runs the `deep` fuzz profile and mutmut. Neither gates a merge: each takes minutes to hours and produces a report to read rather than a pass/fail signal, so both live outside `backend.yml`.

### Schedule and gate

The cron fires on Saturdays at 02:17 UTC (04:17 in Belgrade in summer, 03:17 in winter), so results are waiting on the first workday. It avoids the top of the hour, when GitHub says scheduled runs are most often delayed and, under enough load, dropped.

The `gate` job runs `.github/scripts/deep-sweeps-gate.sh`. A manual run starts whichever sweeps its `sweeps` input selects, unconditionally. A scheduled run decides per sweep, from that sweep's last successful run: the newest completed run of this workflow on `master`, among the last 50, in which that sweep's job concluded `success`. Manual runs count. A failed, cancelled or skipped sweep job does not, so a broken sweep is retried the next Saturday.

| Last successful run | Its age | Its commit | Churn since that commit | Scheduled sweep |
|---|---|---|---|---|
| none among the last 50 runs | | | | runs |
| found | under `MIN_DAYS_SINCE_LAST_SWEEP` (13 days) | | | skipped |
| found | 13 days or more | not in history | unknown | runs, with a warning |
| found | 13 days or more | in history | `CHANGE_THRESHOLD` (200 lines) or more | runs |
| found | 13 days or more | in history | under 200 lines | skipped |

The weekly cron and the 13-day minimum make the schedule at most fortnightly; 13 rather than 14 absorbs the scheduler's delay, so a sweep that started late two Saturdays ago is still old enough. Churn is lines added plus lines removed in `accounts`, `commons`, `monitoring`, `notif` and `ops`, leaving out tests and migrations, between the last successful run's commit and the commit under test. New tests alone can move the mutation score, but they do not count. Diffing from that commit, rather than over a date window, counts exactly the code the last sweep did not see. A commit missing from history (a force-pushed `master`) leaves churn unknown, and the sweep runs rather than skipping silently.

The gate's job summary gives each sweep's decision, last successful run, age in days and churn.

### Steps

| Step | Behaviour |
|---|---|
| Deep schema fuzz | `continue-on-error`: findings are expected, and the uploaded report is the deliverable, so they do not fail the job. `set -o pipefail` gives the step pytest's exit status instead of `tee`'s, so a run that fails, or never collects, is still recorded as a failed step. |
| Mutation sweep | `continue-on-error`: surviving mutants do not fail `mutmut run`, but a broken baseline or a timeout does, and the results collected so far are still worth uploading. The step's timeout sits below the job's so the collect and upload steps still run; mutmut saves each verdict as it lands (`register_result` in `mutmut/mutation/data.py`). |
