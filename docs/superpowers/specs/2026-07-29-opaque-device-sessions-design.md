# Opaque device-session auth (replaces JWT + refresh rotation)

Date: 2026-07-29. Status: draft v10 — eighth review round: web credential
model simplified to platform-owned state, document restructured.

## Why

The JWT hybrid (20-min access token + DB refresh families with rotation, theft
detection, grace windows) exists to make stateless tokens revocable. At Notif's
scale (single user, SQLite on one box) statelessness saves one indexed read per
request and costs the majority of the auth code — and every major review
finding to date (rotation vs. keystore persistence, logout fences, origin
pinning) lives in that machinery. Cookies on native were pure ceremony: a
native app needs a bearer secret in secure storage, not Set-Cookie parsing.

## 1. Goals and invariants

- One opaque session token, one server-side row, one transport per session.
- **The platform owns the credential.** Native: one keystore record. Web: the
  HttpOnly cookie itself, held by the browser. The client keeps no shadow
  copy of credential state, so credential state cannot desynchronize from a
  shadow of it.
- Server state is authoritative. Client-side auth state is a cache of it,
  refreshed by requests; concurrency resolves as **last server-committed
  operation wins**.
- A session ends client-side only on a response that provably says so:
  401 + `WWW-Authenticate: Session` on a designated request (§5).
- Everything that can grow, stall, or retry is bounded; lifetimes are
  deploy-time-tunable configuration, not code constants.

## 2. DeviceSession model and lifetime

Model `DeviceSession` (accounts app; pruned from `RefreshSessionFamily`, new
migrations, deployed history untouched):

- `user` FK, `public_id` UUID (the handle used by the sessions UI)
- `token_hash` — SHA-256 hex of the raw token, `unique=True` (which already
  indexes it)
- `transport` enum (`cookie` | `bearer`) — a token presented through the
  other transport is rejected, and the sessions UI shows web vs native
- `device_label` (<=120 chars), `ip`, `user_agent` (truncated to 256)
- `created_at`, `last_used_at`
- `revoked_at` / `revoke_reason` (logout, revoked_by_user, password_change,
  login_replaced, capacity_evicted, user_deactivated) — natural expiry is
  represented by time, not a reason

Raw token: `secrets.token_urlsafe(32)`; only the hash is stored.

**Lifetime.** No stored expiry columns. A session is live iff not revoked,
`now < last_used_at + idle_lifetime`, and `now < created_at +
absolute_lifetime`. Both lifetimes live in the existing pydantic env config
(`SESSION_IDLE_LIFETIME_DAYS`, default 14; `SESSION_ABSOLUTE_LIFETIME_DAYS`,
default 90), deliberately left unset in `.env` files so the defaults apply
and tuning needs no code change. The cookie `Max-Age` follows the absolute
lifetime. Server-side expiry is authoritative regardless of cookie lifetime.

There is no remember-me split: every session is remembered, and the devices
list is the answer to "I logged in somewhere I should not have" — revoke it.
(The old stack already defaulted `remember_me` to true.)

`last_used_at` advances via one conditional SQL update
(`UPDATE ... SET last_used_at = now WHERE last_used_at < now - 1h`) so
concurrent requests cannot defeat the write damping on SQLite.

**Bounded growth.** At most 20 live sessions per user — the count, create and
evict run in one transaction (SQLite `BEGIN IMMEDIATE` serializes writers),
evicting least-recently-used with reason `capacity_evicted`. The existing
cleanup command deletes rows dead (revoked or expired) for more than 30 days.
The sessions list returns live sessions only, so the 20-row cap bounds the
response and no pagination is needed (the repo defines no global DRF
pagination to inherit).

## 3. Authentication and endpoints

**Auth class** (DRF `SessionTokenAuthentication`):

- Reads `Authorization: Session <token>` first, else the `notif_session`
  cookie. Hash → row lookup. A session is rejected if revoked, past expiry
  (§2), or its user is inactive — `User.delete()` soft-deletes by setting
  `is_active=False`, and a custom row authenticator gets no
  `user_can_authenticate` protection for free. Deactivation/soft-delete
  revokes all the user's sessions in the same transaction
  (`user_deactivated`), so reactivating an account cannot resurrect them.
- **Rejection is asymmetric by transport.** A dead **cookie** resolves as no
  credential (`return None`, anonymous): the browser attaches it to every
  `/api/v1/` request, so raising would 401 every intentionally-anonymous
  endpoint — password reset request/confirm, registration, client events,
  the health probe (breaking outage recovery) — for up to the absolute
  lifetime after a session dies, and a per-endpoint
  `authentication_classes = []` inventory is a maintenance trap. A dead
  **bearer** header still raises: it is a deliberate per-request credential
  (DRF's own TokenAuthentication convention). Protected endpoints lose
  nothing: with authenticators present and none successful, DRF's permission
  denial raises `NotAuthenticated` — still 401 with
  `WWW-Authenticate: Session`.
- Implements `authenticate_header()` (returns `Session`) so authentication
  failures are 401 with `WWW-Authenticate: Session`, never DRF's 403
  coercion. That header is how the client tells our rejection from an edge
  401.
- Cookie-authenticated requests enforce Django CSRF explicitly (the
  authenticator calls the same check `SessionAuthentication.enforce_csrf`
  uses; a custom authenticator does not inherit it). Bearer requests are
  CSRF-exempt (no ambient credential).
- Places the `DeviceSession` row in `request.auth`, so views (password
  change, sessions list) can identify the caller's own session.

**Endpoints** (replace `/token/*`):

| Endpoint | Auth | CSRF | Notes |
|---|---|---|---|
| `POST /auth/login/` | none (`authentication_classes = []`, `AllowAny`) | JSON-only / non-simple-request gate | transport-exclusive issuance, see below |
| `POST /auth/logout/` | none (same) | gate + liveness-conditional CSRF | idempotent, see below |
| `GET /auth/sessions/` | session | n/a (read) | live sessions only: public_id, device_label, transport, created_at, last_used_at, ip, user_agent, current |
| `DELETE /auth/sessions/{public_id}/` | session | cookie transport: yes | revoke one |
| `POST /auth/sessions/revoke_all/` | session | cookie transport: yes | revokes all but the caller's session (same semantics change_password uses today) |

`authentication_classes = []` on login and logout because DRF authenticates
before permission checks and rethrows failures: a stale cookie riding along
must not 401 the request before the view runs. `AllowAny` because the global
default permission is `IsAuthenticated`, which would reject the
now-anonymous caller (master's token views already carry `AllowAny`).

**Login.** Takes credentials + `device_label` + `transport: "cookie" |
"bearer"`. Keeps the existing JSON-only / non-simple-request defense.
Transports are mutually exclusive:

- `cookie` (web): sets HttpOnly `SameSite=Strict; Secure; Path=/api/v1/`
  cookie (`Max-Age` = absolute lifetime), returns **no token** in the body,
  and rotates the CSRF token so Django emits the readable `csrftoken`
  cookie.
- `bearer` (native): returns the raw token once in JSON, sets **no cookie**.
- A live session presented with the login request is revoked
  (`login_replaced`) in the same transaction that creates its replacement,
  so web re-logins do not accumulate orphaned live rows.
- The session-creation transaction re-reads the user row and aborts with 401
  if the password hash differs from the one the credentials were just
  validated against **or the user is no longer active**: a login checked
  against the old password (or a since-deactivated account) must not commit
  a session after a concurrent password change/reset/deactivation has
  revoked everything. The hash comparison is string equality — no second KDF
  run — and `BEGIN IMMEDIATE` guarantees the re-read sees any committed
  change.
- Both responses carry `Cache-Control: no-store`.

**Logout.** Idempotent. Keeps the same JSON-only / non-simple-request gate,
and the rejection path emits no `Set-Cookie`: a cross-site top-level form
POST omits the `SameSite=Strict` cookie but browsers still *apply*
`Set-Cookie` on such responses, so an ungated logout would let any origin
delete a session it never held — the defense master's logout already
encodes, and the only one possible for the legacy-path deletion below, which
cannot be conditioned on presentation. Past the gate the view does a
tolerant manual token lookup (revoking the row when one matches), enforces
the cookie-CSRF check itself, and deletes the session cookie
unconditionally. CSRF is conditional on liveness: a live cookie session
requires a valid CSRF token before it is revoked; an expired, revoked, or
unknown cookie is cleared without one (clearing a dead cookie is not a
protected mutation). Until the cutover ages out, the response also deletes
the legacy `notif_refresh` cookie at its old `/api/v1/token/` path, which no
new-cookie deletion reaches.

**Password paths.** Semantics carry over 1:1 from master: change_password
revokes all but the caller's session; reset-confirm (unauthenticated, no
current session) revokes all — each atomic with the password write.

**Deleted**: refresh endpoint, rotation, token records, theft detection,
grace window, simplejwt issuance/claims.

## 4. Credential storage

**Native (bearer).** One secure record `{token, origin}` in
`flutter_secure_storage` (existing seam + backup exclusion). Its existence
*is* the restoration intent; there is no separate flag to drift out of sync.
Requests attach `Authorization: Session <token>`, and only ever to the
origin recorded at login. Bearer origins must be HTTPS — a long-lived token
never travels over plaintext — with an explicit loopback allowance for
development. Logout deletes the record locally even when the server is
unreachable (the credential is gone from the device; the orphaned row stays
visible in the sessions UI and dies at idle expiry). A failed keystore
delete is reported (client event + UI) instead of claiming a durable
sign-out a later cold start would undo.

**Web (cookie).** The HttpOnly cookie is the only persistent auth state; the
client stores nothing. The browser already scopes the cookie to the origin
that set it, and cookie-backed web auth is declared **same-origin-only** —
not merely same-site: the `csrftoken` cookie is host-scoped, so JS on
`app.example.com` cannot read one set by `api.example.com`. A
non-same-origin backend URL on web is rejected at settings time (the
existing diagnostic becomes a validation); no `SameSite=None`, no
CSRF-bootstrap endpoint. This matches the actual deployment (Caddy serves
app and API from one origin). `withCredentials` stays; the CSRF token is
read from the `csrftoken` cookie and attached as `X-CSRFToken` on writes.

Dev exception: loopback hosts compare host-only (ports ignored), because
Flutter's dev server and Django use different ports — verified in the
supported browser, since RFC 6265 leaves secure-channel semantics to the
user agent. The client-side allowance is not enough by itself: Django's CSRF
origin comparison is port-exact (CORS already admits arbitrary loopback
ports; `CSRF_TRUSTED_ORIGINS` does not), so dev pins the Flutter web port
(`--web-port`) and dev-only settings list that exact loopback origin in
`CSRF_TRUSTED_ORIGINS`; production lists only the deployed origin.

## 5. State transitions and concurrency

States: Anonymous / Restoring / Authenticated / Unavailable / Expired /
LoggingOut (refresh states deleted).

**Cold start.**
- Native: if the keystore record exists, one designated
  `GET /accounts/users/get_my_info/`; otherwise Anonymous with no request.
- Web: always one designated `GET /accounts/users/get_my_info/` with
  credentials — the cookie, if present, is invisible to JS, so the probe is
  how the app learns its own auth state. An anonymous cold start costs one
  401; accepted at this scale.
- Probe outcomes, both platforms: 200 → Authenticated; 401 bearing
  `WWW-Authenticate: Session` → Anonymous (native also deletes its record);
  transport failure or 401 without the header → Unavailable + the existing
  bounded health-probe recovery (the health endpoint stays reachable under a
  dead cookie because of the dead-cookie-resolves-anonymous rule, §3).

**Designated requests.** A request is *designated session-bearing* when the
app issues it in (or entering) an authenticated state: native verifiably
attaches the token; web relies on the designation since it cannot see its
HttpOnly cookie. A 401 ends the session only when all three hold: current
generation, designated request, and `WWW-Authenticate: Session` on the
response. Then: Expired (native deletes its record). Edge-infrastructure
401s and unauthenticated calls change nothing. 403 never touches session
state and never means "unavailable": it surfaces as a request-level
forbidden/CSRF failure on the screen that made the request.

**Generation.** A single monotonically increasing auth generation:
responses (401s included) dispatched under an older generation are ignored,
so a slow response from before a logout/login transition cannot corrupt the
new state. The generation gates *response handling* and app-issued
designated requests; it cannot fence the browser itself — the browser
applies `Set-Cookie` from any response and attaches the cookie to any
credentialed request regardless of app state. That is harmless under §1:
server state is authoritative and the app's next designated request
reconciles it.

**Login/logout serialization.** Within one runtime (tab / app instance),
login and logout serialize behind one auth-mutation lock. Across browser
tabs there is deliberately no lock, no fence, and no compensation: the
outcome of concurrent tab operations is whatever the server committed last.
A login that lands after another tab's logout leaves you logged in — with
the session visible and revocable in the sessions UI. (v7–v9 carried a
logout-nonce + targeted self-revocation protocol here; it was removed —
see appendix.)

**Web logout is server-acknowledged.** Only the server can clear an HttpOnly
cookie, so web logout succeeds only when the server confirms it. If the
server is unreachable, the UI reports that logout could not be completed and
the app enters Unavailable — it does not manufacture a local "signed out"
the browser cannot enforce. Native logout, whose local credential delete is
genuinely effective, stays best-effort as in §4.

## 6. Delivery and cutover

1. Merge #61 (auth-agnostic, survives untouched). Close #68 unmerged; park
   the branch — its secure-store plumbing, backup rules, state machine and
   test harnesses get cherry-picked into the new branch.
2. New branch `feat/opaque-device-sessions` off master: backend commit(s),
   then frontend commit(s), OpenAPI regenerated, contract tests mirroring
   the trigger-scrape pattern for login/logout/sessions.
3. **Maintenance cutover, accepted explicitly**: backend stops accepting
   JWTs; every client is force-logged-out. Web deploy is cache-busted; the
   new frontend's first run deletes legacy credentials (old keystore
   entries, old preference keys), and the new login/logout responses expire
   the legacy `notif_refresh` cookie at its old path until the cutover ages
   out. Native builds older than the cutover cannot authenticate and must
   upgrade. With zero users this costs nothing; the spec records it so
   nobody mistakes "deploy together" for atomicity.

## 7. Test matrix

Backend:
- Auth class: both transports authenticate; wrong-transport rejection;
  401-not-403 via `authenticate_header`; dead cookie resolves anonymous
  across the anonymous inventory (reset request/confirm, registration,
  client events, health); dead cookie on protected endpoint → 401 with
  `WWW-Authenticate`; dead bearer raises; inactive-user rejection;
  deactivation revokes atomically.
- Lifetime: idle/absolute expiry boundaries honoring the config settings;
  damped `last_used_at` under concurrency.
- Login: transport-exclusive issuance; login-replacement revocation;
  concurrent login-vs-password-change, login-vs-reset and
  login-vs-deactivation (in-transaction re-read aborts); session cap
  eviction under concurrent logins.
- Logout: idempotent incl. dead cookies; liveness-conditional CSRF;
  cross-site form POST rejected with no `Set-Cookie`; legacy cookie
  deletion.
- CSRF enforced on cookie writes, absent on bearer; deterministic
  token-hash test; password-path atomicity tests carried over.

Frontend:
- auth_service_test adapted: cold-start probe paths (200 / session 401 /
  outage) per platform; stale-generation 401 ignored; designated-request
  401 triple condition; web logout offline → reported failure, state
  Unavailable, no local sign-out; native logout offline → local delete +
  reported orphan.
- api_client CSRF attach; architecture tests keep keystore/dio boundaries;
  drift check pins the schema.

## 8. Appendix: considered and rejected

- Login CSRF protection beyond the JSON-only defense: a cross-site login
  POST with a JSON body is a non-simple request, blocked by CORS preflight.
- Tighter `last_used_at` damping: at 1h damping the idle check is at most 1h
  stale against a default 14-day window — irrelevant.
- **Cross-tab logout fencing (logout nonce + targeted self-revocation,
  v7–v9).** Three review rounds built a protocol so a login completing
  after another tab's logout would revoke itself. Removed: the compensating
  revocation is itself a network request that can fail, so the "no session
  survives logout" guarantee was illusory — and the protocol spread across
  the login contract, persistence layer, state machine and tests. With no
  background refresh, the race needs simultaneous human login and logout in
  different tabs; last-server-committed-wins plus the sessions UI is the
  honest semantics. Web Locks (`navigator.locks`) rejected for the same
  reason plus web-only interop `flutter test` cannot exercise; if absolute
  cross-tab ordering is ever genuinely required, put it behind one small
  web-only locking abstraction rather than a distributed protocol.
- **A persistent web auth record** (`restoreIntent` marker, stored web
  origin): removed with the always-probe cold start. Same-origin-only means
  the cookie's origin is the configured backend origin by construction, and
  the browser enforces cookie scoping anyway; a JS-side record can only
  desynchronize from the HttpOnly cookie it shadows (crash between
  `Set-Cookie` and a record write leaves a live ambient credential with no
  intent, or vice versa).
- Remember-me split: dropped in v3 — every session is remembered; the
  devices list covers the "untrusted login" case.
- `Secure` cookie breaking local web dev: Chromium accepts Secure cookies
  from trustworthy loopback origins, so the flag is kept unconditionally;
  the real dev friction was the port mismatch, handled in §4.
- CSRF-bootstrap endpoint: unnecessary under the same-origin-only rule.

## Out of scope

Multi-user hardening (rate limits exist), OAuth/social login, API keys for
third parties, `SameSite=None` support, offline-logout tombstones.
