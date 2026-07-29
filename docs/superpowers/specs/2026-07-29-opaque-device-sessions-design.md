# Opaque device-session auth (replaces JWT + refresh rotation)

Date: 2026-07-29. Status: draft v3 - design review incorporated, remember-me split removed.

## Why

The JWT hybrid (20-min access token + DB refresh families with rotation, theft
detection, grace windows) exists to make stateless tokens revocable. At Notif's
scale (single user, SQLite on one box) statelessness saves one indexed read per
request and costs the majority of the auth code — and every major review
finding to date (rotation vs. keystore persistence, logout fences, origin
pinning) lives in that machinery. Cookies on native were pure ceremony: a
native app needs a bearer secret in secure storage, not Set-Cookie parsing.

## Design

One opaque session token, one server-side row, one transport per session.

### Backend

**Model `DeviceSession`** (accounts app; pruned from `RefreshSessionFamily`,
new migrations, deployed history untouched):

- `user` FK, `public_id` UUID (the handle used by the sessions UI)
- `token_hash` — SHA-256 hex of the raw token, `unique=True` (which already
  indexes it)
- `device_label`, `ip`, `user_agent`
- `created_at`, `last_used_at`
- `revoked_at` / `revoke_reason` (logout, revoked_by_user, password_change,
  login_replaced) — natural expiry is represented by time, not a reason

No stored expiry columns. A session is live iff not revoked,
`now < last_used_at + 14d` (idle), and `now < created_at + 90d` (absolute
cap). There is no remember-me split: every session is remembered, and the
devices list is the answer to "I logged in somewhere I should not have" —
revoke it. (The old stack already defaulted `remember_me` to true.)

`last_used_at` advances via one conditional SQL update
(`UPDATE ... SET last_used_at = now WHERE last_used_at < now - 1h`) so
concurrent requests cannot defeat the write damping on SQLite.

Raw token: `secrets.token_urlsafe(32)`; only the hash is stored.

**Auth class** (DRF `SessionTokenAuthentication`):
- Reads `Authorization: Session <token>` first, else the `notif_session`
  cookie. Hash → row lookup; reject if revoked or past expiry as above.
- Implements `authenticate_header()` (returns `Session`) so authentication
  failures are 401, never DRF's 403 coercion — "401 means dead session" is
  load-bearing for the client.
- Cookie-authenticated requests enforce Django CSRF explicitly (the
  authenticator calls the same check `SessionAuthentication.enforce_csrf`
  uses; a custom authenticator does not inherit it). Header-authenticated
  requests are CSRF-exempt (no ambient credential).
- Places the `DeviceSession` row in `request.auth`, so views (password change,
  sessions list) can identify the caller's own session.

**Endpoints** (replace `/token/*`; login keeps the existing JSON-only /
non-simple-request defense it has today):

- `POST /auth/login/` — credentials + `device_label` +
  `transport: "cookie" | "bearer"`. Transports are mutually exclusive:
  - `cookie` (web): sets HttpOnly `SameSite=Strict; Secure; Path=/api/v1/`
    cookie (`Max-Age` = 90d) — returns **no token** in the body, and rotates
    the CSRF token so Django emits the readable `csrftoken` cookie.
  - `bearer` (native): returns the raw token once in JSON, sets **no cookie**.
  - Both responses carry `Cache-Control: no-store`. Server-side expiry is
    authoritative regardless of cookie lifetime.
- `POST /auth/logout/` — idempotent: always deletes the cookie (expired,
  revoked, or missing sessions included — the view allows unauthenticated
  calls precisely so a dead cookie can still be cleared) and revokes the row
  when one authenticates. Offline logout is best-effort: native deletes its
  keystore token, web clears its marker; the orphaned row dies at idle/cap
  expiry and remains visible/revocable in the sessions UI. No tombstones.
- `GET /auth/sessions/` — list (public_id, device_label, created_at,
  last_used_at, ip, user_agent, current: bool).
- `DELETE /auth/sessions/{public_id}/` — revoke one.
- `POST /auth/sessions/revoke_all/` — revokes all but the caller's session
  (same semantics change_password uses today).

**Deleted**: refresh endpoint, rotation, token records, theft detection, grace
window, simplejwt issuance/claims. Password-change/reset revocation semantics
carry over 1:1 (revoke all but current, atomic with the password write).

### Frontend

- Native: bearer transport; token in `flutter_secure_storage` (existing seam +
  backup exclusion); attach `Authorization: Session <token>`.
- Web: cookie transport; `withCredentials` stays; CSRF token read from the
  `csrftoken` cookie and attached as `X-CSRFToken` on writes. Cookie-backed
  web auth is declared same-site-only: a cross-site backend URL on web is
  rejected at settings time (the existing diagnostic becomes a validation),
  not papered over with `SameSite=None`.
- State machine kept minus refresh states: Anonymous / Restoring /
  Authenticated / Unavailable / Expired / LoggingOut. A single monotonically
  increasing auth generation remains: responses (401s included) dispatched
  under an older generation are ignored, so a slow request from a
  logged-out-then-logged-in-again window cannot kill the new session. This is
  the only piece of the old choreography that survives, because it guards the
  network boundary, not rotation.
- Cold start: if the remembered-session marker is set, one
  `GET /accounts/users/get_my_info/`; transport failure → `AuthUnavailable` +
  existing bounded health-probe recovery; 401 (current generation) → Expired
  (marker set) or Anonymous.
- Any current-generation 401 mid-session → Expired. 403 never touches session
  state and never means "unavailable": it surfaces as a request-level
  forbidden/CSRF failure on the screen that made the request.
- Session-origin pinning survives as one rule: the token/cookie is only ever
  sent to the origin recorded at login.
- **Deleted**: `refresh_cookie_store.dart` entirely, refresh choreography and
  single-flight in `auth.dart`, rotation-related tests.

## Delivery

1. Merge #61 (auth-agnostic, survives untouched). Close #68 unmerged; park the
   branch — its secure-store plumbing, backup rules, state machine and test
   harnesses get cherry-picked into the new branch.
2. New branch `feat/opaque-device-sessions` off master: backend commit(s),
   then frontend commit(s), OpenAPI regenerated, contract tests mirroring the
   trigger-scrape pattern for login/logout/sessions.
3. **Maintenance cutover, accepted explicitly**: backend stops accepting JWTs;
   every client is force-logged-out. Web deploy is cache-busted; the new
   frontend's first run deletes legacy credentials (old refresh cookie via the
   idempotent logout call, old keystore entries, old preference keys). Native
   builds older than the cutover cannot authenticate and must upgrade. With
   zero users this costs nothing; the spec records it so nobody mistakes
   "deploy together" for atomicity.

## Testing

Backend: auth-class tests (both transports; CSRF enforced on cookie writes and
absent on bearer; 401-not-403 via `authenticate_header`; idle/cap expiry
boundaries; damped `last_used_at` under concurrency; revocation; idempotent
logout incl. unauthenticated), deterministic token-hash test, atomicity tests
carried over. Frontend: adapted auth_service_test (restore/outage/expired
paths, stale-generation 401 ignored), api_client CSRF attach, architecture
tests keep keystore/dio boundaries; drift check pins the schema.

## Out of scope

Multi-user hardening (rate limits exist), OAuth/social login, API keys for
third parties, `SameSite=None` support, offline-logout tombstones.
