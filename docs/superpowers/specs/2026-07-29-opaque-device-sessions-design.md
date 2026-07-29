# Opaque device-session auth (replaces JWT + refresh rotation)

Date: 2026-07-29. Status: draft v4 - second review round incorporated.

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
- `transport` enum (`cookie` | `bearer`) — a token presented through the
  other transport is rejected, and the sessions UI can show web vs native
- `device_label` (<=120 chars), `ip`, `user_agent` (truncated to 256)
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

Bounded growth: at most 20 live sessions per user (login evicts the
least-recently-used beyond the cap); the existing cleanup command deletes
rows dead (revoked or expired) for more than 30 days; the sessions list is
paginated with the standard page size.

**Auth class** (DRF `SessionTokenAuthentication`):
- Reads `Authorization: Session <token>` first, else the `notif_session`
  cookie. Hash → row lookup; reject if revoked or past expiry as above.
- Implements `authenticate_header()` (returns `Session`) so authentication
  failures are 401 with `WWW-Authenticate: Session`, never DRF's 403
  coercion. That header is how the client tells our rejection from an edge
  401 — "401 means dead session" holds only for responses that carry it.
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
  - A live session presented with the login request is revoked
    (`login_replaced`) in the same transaction that creates its replacement,
    so web re-logins do not accumulate orphaned live rows.
  - Both responses carry `Cache-Control: no-store`. Server-side expiry is
    authoritative regardless of cookie lifetime.
- `POST /auth/logout/` — idempotent, with `authentication_classes = []`:
  DRF authenticates before permission checks and rethrows failures, so an
  installed authenticator would 401 an expired cookie before the view could
  clear it. The view instead does a tolerant manual token lookup (revoking
  the row when one matches), enforces the cookie-CSRF check itself, and
  unconditionally deletes the session cookie — and, until the cutover is
  aged out, the legacy `notif_refresh` cookie at its old
  `/api/v1/token/` path, which no new-cookie deletion reaches. Offline logout is best-effort: native deletes its
  keystore token, web clears its marker; the orphaned row dies at idle/cap
  expiry and remains visible/revocable in the sessions UI. No tombstones —
  but local credential and marker mutations report their failures (client
  event + UI): if this device could not clear its keystore token or marker,
  the logout screen says so instead of claiming a durable sign-out that a
  later cold start would undo.
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
  web auth is declared **same-origin-only** — not merely same-site: the
  `csrftoken` cookie is host-scoped, so JS on `app.example.com` cannot read
  one set by `api.example.com`. A non-same-origin backend URL on web is
  rejected at settings time (the existing diagnostic becomes a validation);
  no `SameSite=None`, no CSRF-bootstrap endpoint. This matches the actual
  deployment (Caddy serves app and API from one origin).
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
- A 401 ends the session only when all three hold: current generation, the
  request actually carried the current session credential, and the response
  bears `WWW-Authenticate: Session`. Edge-infrastructure 401s and
  unauthenticated calls change nothing. 403 never touches session state and never means "unavailable": it surfaces as a request-level
  forbidden/CSRF failure on the screen that made the request.
- Session-origin pinning survives as one rule: the token/cookie is only ever
  sent to the origin recorded at login. Bearer origins must be HTTPS — a
  90-day token never travels over plaintext — with an explicit loopback
  allowance for development.
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
   frontend's first run deletes legacy credentials (old keystore entries, old
   preference keys), and the new login/logout responses expire the legacy
   `notif_refresh` cookie at its old path until the cutover ages out. Native
   builds older than the cutover cannot authenticate and must upgrade. With
   zero users this costs nothing; the spec records it so nobody mistakes
   "deploy together" for atomicity.

## Testing

Backend: auth-class tests (both transports; CSRF enforced on cookie writes and
absent on bearer; 401-not-403 via `authenticate_header`; idle/cap expiry
boundaries; damped `last_used_at` under concurrency; revocation; idempotent
logout incl. dead cookies and CSRF), wrong-transport rejection, session cap
eviction, login-replacement revocation, deterministic token-hash test,
atomicity tests carried over. Frontend: adapted auth_service_test (restore/outage/expired
paths, stale-generation 401 ignored), api_client CSRF attach, architecture
tests keep keystore/dio boundaries; drift check pins the schema.

## Out of scope

Multi-user hardening (rate limits exist), OAuth/social login, API keys for
third parties, `SameSite=None` support, offline-logout tombstones.
