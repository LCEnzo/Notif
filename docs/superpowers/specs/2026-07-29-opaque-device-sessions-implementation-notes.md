# Implementation notes: opaque device sessions

Notes on where the spec (`2026-07-29-opaque-device-sessions-design.md`, draft
v10) was underdetermined, wrong, or assumed a starting point that this branch
does not have. The spec itself is untouched.

## 1. The delivery plan's starting point does not exist here

Spec §6 says: merge #61, then cherry-pick #68's "secure-store plumbing, backup
rules, state machine and test harnesses" into the new branch.

The branch base (`4775c1f`) is master plus the spec commits. Master's frontend
has **none** of that: no `flutter_secure_storage`, no `AppFailure` /
`FailureCategory`, no `PreferenceStore`, no auth state machine, no
`architecture_test.dart`, and the JWT lived in a plain in-memory field. So
everything §4/§5 describes as "cherry-picked" was written from scratch here:

- `frontend/lib/services/session_store.dart` — the keystore seam and the
  `{token, origin}` record.
- `frontend/lib/services/auth.dart` — the sealed state machine, the generation
  counter, the auth-mutation lock, the cold-start probe.
- `frontend/test/architecture_test.dart` — the keystore/dio boundaries §7 asks
  the architecture tests to keep.
- `frontend/test/support/auth_test_harness.dart` — the fake adapter and
  in-memory store the frontend matrix needs.

Consequence for review: this is a fresh implementation of those pieces, not a
port. It will not match #68 line for line, and the failure classification in
`AppFailure` terms that AGENTS.md describes does not exist to hook into — auth
failures are classified by the state machine (`AuthUnavailable` vs
`AuthAnonymous` vs `AuthExpired`) and request failures still surface as strings.

## 2. Removing JWTs removed the client's knowledge of its own user id

Not mentioned anywhere in the spec. `POST /monitoring/links/` requires a `user`
field in the body, and the old client filled it from the `user_id` claim it
decoded out of the access token. An opaque token carries no claims.

Fix taken: `UserFullReadSerializer` now exposes `id`, so the designated probe
(`GET /accounts/users/get_my_info/`) is where the client learns its own id.
That is a one-field schema addition and keeps the monitoring contract as-is.

The alternative — having `LinkViewSet.perform_create` set `user` from
`request.user` and drop it from the payload — is the better design, and worth
doing, but it changes the monitoring API and is outside this spec.

## 3. `POST /auth/login/`'s response body is unspecified

§3 says cookie logins return "no token" and bearer logins return "the raw token
once", but never names the response shape. Implemented as
`{transport, public_id, token}` with `token: null` on the cookie path, so one
serializer covers both and the OpenAPI schema has something to say. `public_id`
is included so a client can point at its own row in the sessions list
immediately.

Also unspecified: what the sessions list's `DELETE` returns. Implemented as
`200 {"status": "ok", "revoked": 1}` to match `revoke_all/`'s shape rather than
DRF's default `204` — nothing is deleted, a row is revoked, and one response
shape for both is easier to consume.

## 4. The X-Refresh-Request header signal was dropped, not carried over

§3 says login and logout keep "the existing JSON-only / non-simple-request
defense". Master accepted *either* `X-Refresh-Request: 1` or a JSON content
type. The header was a refresh-endpoint artefact and the refresh endpoint is
gone, so only the JSON content-type branch survives
(`accounts.views._require_json_request`). A JSON body already proves the
request was not a cross-site form, and it forces a CORS preflight; the header
added nothing that the content type did not.

## 5. §7's "under concurrency" tests are serialised, deliberately

The matrix asks for "damped `last_used_at` under concurrency", "session cap
eviction under concurrent logins", and "concurrent login-vs-password-change".
Real thread-level concurrency against SQLite inside `pytest-django`'s
transactional test case is not reproducible enough to be worth the flake
budget, and `BEGIN IMMEDIATE` means concurrent writers *do* serialise in
production. So:

- damping is tested with two separately-fetched instances of the same row,
  which is exactly the stale-read the conditional `UPDATE` exists to survive;
- the cap is tested by driving more logins than the cap allows;
- the login-vs-{password change, reset, deactivation} races are tested by
  calling `create_session()` with the password hash captured *before* the
  competing write, which is the precise interleaving the in-transaction re-read
  defends against.

These test the invariant rather than the scheduler. If the reviewer wants true
concurrency, it needs `TransactionTestCase` plus real threads, and it will be
slow and occasionally flaky.

## 6. Unavailable is not anonymous, and the router had to learn that

§5 says a failed web logout leaves the app in Unavailable rather than
manufacturing a local sign-out. A router that keys purely on "is authenticated"
renders Unavailable as the login screen — which is exactly the manufactured
sign-out the spec forbids. The router therefore treats Restoring, Unavailable
and LoggingOut as *undecided* and routes them to a `/starting` screen that
names the problem and offers a retry (re-running the probe). This is an
addition to the spec, not a deviation from it, but it is load-bearing.

## 7. Sessions UI

§2 and §8 both lean on the sessions list as the thing that makes
last-server-committed-wins acceptable, but §7's frontend matrix does not ask
for it and master shipped the old `/sessions/` endpoints with no Dart consumer
at all. A devices section was added to the account screen
(`frontend/lib/services/device_sessions.dart` plus `_DeviceSessionsSection` in
`account.dart`) so the argument the design rests on is actually true. It is
deliberately plain — list, revoke one, revoke others — and has no widget test
yet.

## 8. Smaller things

- **`device_label` over 120 chars is a 400, not a silent truncation.** The
  serializer enforces `max_length=120`; the service layer also truncates as
  defence in depth. Spec says "<=120 chars" without saying which.
- **`DEV_WEB_PORT`** (default 5353) is a new backend config field. §4 requires
  dev to pin the Flutter web port and list that exact loopback origin in
  `CSRF_TRUSTED_ORIGINS`; the port had to live somewhere both the Django
  settings and `run-local-dev.{sh,ps1}` could read.
- **`djangorestframework-simplejwt` was removed from `pyproject.toml`** and the
  lockfile regenerated. §3 says simplejwt issuance is deleted; leaving an
  unused auth library installed would contradict that.
- **The cleanup command was renamed** `cleanup_refresh_sessions` →
  `cleanup_device_sessions`, and `run_due_tasks`'s maintenance summary key
  changed from `refresh_session_families_deleted` /
  `refresh_token_records_deleted` to `device_sessions_deleted`. Anything
  reading those SystemEvent details will see the new key.
- **`ops.views._SECRET_PATTERNS`** now scrubs `Session <token>` and
  `notif_session=` alongside the legacy patterns, so the client-event sink
  cannot become a place session tokens get logged.

## 9. What is not implemented

- No rate-limit tuning beyond renaming `token_logout` → `logout` and dropping
  the refresh/verify scopes.
- No widget test for the devices section.
- The frontend still surfaces request-level failures as exception strings;
  AGENTS.md's `AppFailure` / `FailureCategory` classification does not exist on
  this base and building it was out of scope for this spec.
