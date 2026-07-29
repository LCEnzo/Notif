# Opaque device-session auth (replaces JWT + refresh rotation)

Date: 2026-07-29. Status: draft for review.

## Why

The JWT hybrid (20-min access token + DB refresh families with rotation, theft
detection, grace windows) exists to make stateless tokens revocable. At Notif's
scale (single user, SQLite on one box) statelessness saves one indexed read per
request and costs the majority of the auth code — and every major review
finding to date (rotation vs. keystore persistence, logout fences, origin
pinning) lives in that machinery. Cookies on native were pure ceremony: a
native app needs a bearer secret in secure storage, not Set-Cookie parsing.

## Design

One opaque session token, one server-side row, dual transport.

### Backend

**Model `DeviceSession`** (accounts app; pruned from `RefreshSessionFamily`,
new migrations, deployed history untouched):

- `user` FK, `token_hash` (SHA-256 hex of the raw token, unique, indexed)
- `device_label`, `ip`, `user_agent`
- `created_at`, `last_used_at`
- `expires_at` — sliding: bumped to now+14d on authenticated use, at most
  once per hour (write damping)
- `absolute_expires_at` — now+90d at login, never moves
- `revoked_at` / `revoke_reason` (logout, revoked_by_user, expired) — rows are
  soft-revoked then garbage-collected by the existing cleanup command

Raw token: `secrets.token_urlsafe(32)`; only the hash is stored.

**Auth class** (DRF): reads `Authorization: Session <token>` first, else the
`notif_session` cookie. Hash → row lookup; reject if revoked or past either
expiry; bump sliding expiry. Cookie-authenticated requests enforce Django CSRF
(csrftoken cookie + `X-CSRFToken` header); header-authenticated requests are
CSRF-exempt (no ambient credential).

**Endpoints** (replace `/token/*`):
- `POST /auth/login/` — credentials + `device_label` → sets HttpOnly
  `SameSite=Strict; Secure; Path=/api/v1/` cookie AND returns the raw token
  once in JSON (native stores it in keystore; web ignores it)
- `POST /auth/logout/` — revokes the row, deletes the cookie
- `GET/DELETE /auth/sessions/` — device list + revoke one/all (kept from #62)
- `remember_me=false`: browser-session cookie (no Max-Age) and 24h `expires_at`

**Deleted**: refresh endpoint, rotation, token records, theft detection, grace
window, simplejwt issuance/claims. Password-change/reset revocation semantics
carry over 1:1 (revoke all but current, atomic with the password write).

### Frontend

- Native: token in `flutter_secure_storage` (existing seam + backup
  exclusion); attach `Authorization: Session <token>`.
- Web: cookie only; `withCredentials` stays; CSRF token read from the
  `csrftoken` cookie and attached as `X-CSRFToken` on writes.
- State machine kept minus refresh states: Anonymous / Restoring /
  Authenticated / Unavailable / Expired / LoggingOut. Cold start: if the
  remembered-session marker is set, one `GET /accounts/users/get_my_info/`;
  transport failure → `AuthUnavailable` + existing bounded health-probe
  recovery; 401 → Expired (marker set) or Anonymous.
- Any 401 mid-session → Expired. No refresh, no single-flight, no epochs, no
  retry-after-401.
- Session-origin pinning survives as one rule: the token/cookie is only ever
  sent to the origin recorded at login.
- **Deleted**: `refresh_cookie_store.dart` entirely, refresh choreography in
  `auth.dart`, rotation-related tests. Failure classification: session death
  keys on 401 only (403 = edge infrastructure → degraded, not expiry).

## Delivery

1. Merge #61 (auth-agnostic, survives untouched). Close #68 unmerged; park the
   branch — its secure-store plumbing, backup rules, state machine and test
   harnesses get cherry-picked into the new branch.
2. New branch `feat/opaque-device-sessions` off master: backend commit(s),
   then frontend commit(s), OpenAPI regenerated, contract tests mirroring the
   trigger-scrape pattern for login/logout/sessions.
3. Hard cutover; no users. FE+BE deploy together.

## Testing

Backend: auth-class unit tests (both transports, CSRF enforcement, expiry
sliding + cap + damping, revocation, remember_me=false), property test on
token hashing, atomicity tests carried over. Frontend: adapted
auth_service_test (restore/outage/expired paths), api_client CSRF attach,
architecture tests keep keystore/dio boundaries; drift check pins the schema.

## Out of scope

Multi-user hardening (rate limits exist), OAuth/social login, API keys for
third parties, Django CSRF beyond DRF's standard integration.
