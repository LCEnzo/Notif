# Notif security & deploy audit — 2026-07-03

> **Historical snapshot, not a current security-status page.** This records the
> code and host state examined on 2026-07-03, immediately before remediation
> commits `f0044c8`, `2b8581d`, and `e24f2bb`. Current master uses opaque
> `DeviceSession` credentials rather than the refresh-family JWT design discussed
> below. Revalidate every open item against current code and production before
> acting on it. The status table below covers only findings revalidated while
> importing this snapshot; every unlisted finding remains unverified.

## Import status — 2026-08-02

| Finding | Current disposition |
| --- | --- |
| A1 · outbound-request SSRF | Proposed remediation in PR #76; open until reviewed and merged. |
| A2 · writable Link owner | Fixed on current master. |
| A3 · password changes leave sessions valid | Superseded by the opaque `DeviceSession` implementation; current password/session revocation tests pass. |
| A4 · strategy ownership and plaintext credentials | Ownership isolation is proposed in PR #77; encryption of stored third-party credentials remains open. |
| D3 · sudo deploy misses the user's cron | Proposed remediation in PR #75; open until reviewed and merged. |

PR #78 reports client failures to the existing client-events sink, but it is not
treated as remediation for one of the findings below. Each proposed PR still
requires its own review, tests, and deployment verification.

Branch `deploy-config`. Four parallel auditors (backend auth, backend authz/API,
frontend auth, deploy config) plus lead verification of every HIGH claim against
the code and, where possible, the live VPS. Findings deduplicated and ranked by
real blast radius, not by the reporting agent's local severity.

**Live-box facts established during the audit** (origin IP redacted, up 55 days,
containers up 7 weeks):

- Host is healthy: load ~0.02, 6.7 GiB RAM free, no miner, no failed units, only
  background SSH scanner noise (no successful intrusions; password auth is off,
  root login key-only).
- **Deployed code is `v0.2.0 / a053995` — predates this branch (`v0.3.0`).** The
  5-minute `run_due_tasks` cron is still the live scheduler; no systemd units
  installed yet.
- **No host firewall** (no nftables filter chain, `ufw` absent) and the origin
  serves the full app when you bypass Cloudflare via direct-IP — confirmed live.
- Disk 17 GB used, but **14.4 GB is reclaimable Docker build cache**; the app
  itself is ~80 MB. `docker builder prune -af` drops the box to ~4–6 GB.

The prod container runs `DEBUG=false` with a randomised admin path, so the
`DEBUG`-gated footguns (dev-bootstrap login, MD5 hasher, 48 h tokens,
`CORS_ALLOW_ALL_ORIGINS`) are **off in the live deployment**. Several findings are
conditional on a `DEBUG` misconfig and are marked as such.

---

## The one decision that reframes everything: open registration

`UserViewSet.get_permissions` returns `[]` for `POST` (`accounts/views.py:269-274`),
so **anyone on the internet can self-register, get a JWT, and reach every
authenticated-only endpoint.** For an effectively single-user personal app this is
almost certainly unintended, and it is the master lever: it converts SSRF (A1),
strategy-credential disclosure (A4), writable-owner (A2), and PII enumeration (A6)
from "authenticated-only" into "reachable by any stranger."

**If you want single-user: close registration.** That one change collapses the
practical reachability of A1/A2/A4/A6 to yourself. **If you want multi-user:** the
object-level authz holes (A1–A4) must be fixed before you ever invite a second
user. Everything below is prioritised assuming you'll decide this first.

---

## Priority 1 — fix before the next deploy

### A1 · SSRF: server fetches arbitrary user-supplied URLs — HIGH, confirmed
`monitoring/services.py:69`, `monitoring/strategies.py:123-131`
`scrape_link` calls `strategy.scrape(URL(link.url), …)` with no host check;
`_fetch_url_content` does `requests.get(url, timeout=…)` with default
`allow_redirects=True` and **no private-IP / loopback / link-local filtering**.
A registered user creates a Link with `url=http://169.254.169.254/latest/meta-data/`
(cloud metadata), `http://backend:8000/…`, `http://127.0.0.1:…`, or any LAN
address, then calls `trigger-scrape/`; the backend issues the request from inside
the Docker network / VPS. `FeedStrategy` echoes parseable response bodies into
notification titles the attacker reads back → semi-blind SSRF. Reachable
Cloudflare-bypassed via the origin IP.
*Fix:* resolve the host and reject private/loopback/link-local/multicast ranges
(and re-check after each redirect); bound redirect count; consider an egress
allowlist. This is "external data as external data" applied to *outbound* fetches.

### A2 · Writable `user` FK on `LinkSerializer` — HIGH, confirmed
`monitoring/serializers.py:29-59`
`user` is in `fields` and marked `required`, but **not** in `read_only_fields`,
and `LinkViewSet` has no `perform_create` override. A user POSTs a Link with
`user=<victim_pk>` → the link lands in the victim's account and the scheduler
scrapes it (pollutes their notifications, points their scrapes at attacker URLs);
PATCH can likewise reassign ownership.
*Fix (one line + one method):* move `user` to `read_only_fields`, set
`serializer.save(user=self.request.user)` in `perform_create`.

### A3 · Password reset / change don't revoke sessions — HIGH, confirmed
`accounts/views.py:317-318` (change_password), `:434-438` (reset confirm)
Both call `set_password`/`save` but never revoke the user's
`RefreshSessionFamily` rows, and JWT auth carries no password-hash binding. A
stolen refresh cookie keeps rotating (each rotation mints a fresh 72 h token and
bumps `last_used_at`, so the family never ages out of cleanup). **The account
recovery flow does not actually evict an intruder.**
*Fix:* revoke all of the user's refresh families inside both password-change paths.

### A4 · Cross-tenant strategy-credential disclosure + plaintext creds at rest — HIGH, strongly-supported
`monitoring/serializers.py:22` (`fields="__all__"`), `strategies.py:544,808`,
`monitoring/views.py:75`
`StrategySerializer` exposes `data`, which for `QQAlertsStrategy` /
`KemonoFavouritesStrategy` holds the user's **plaintext third-party
username/password**. `StrategyViewSet` scopes by association
(`Q(link_set__user=u) | Q(link_set__isnull=True)`), but `LinkSerializer.strategy`
is an unscoped `PrimaryKeyRelatedField` over all strategies. An attacker creates
their own Link referencing a victim's strategy PK; that strategy now satisfies
`link_set__user=attacker`, so `GET /strategies/{pk}/` returns the victim's stored
credentials. Two defects stacked: (a) secrets stored plaintext, (b) FK scoping
gap.
*Fix:* scope the strategy FK queryset to the requester; drop `data` (or secret
subfields) from the read serializer; encrypt third-party creds at rest.

### A5 · Login brute-force: throttle keyed on spoofable XFF, no lockout — HIGH, confirmed mechanism
`notif/settings.py:193-208` (no `NUM_PROXIES`), `accounts/views.py:94-105`
With `NUM_PROXIES` unset, DRF's `get_ident` uses the whole `X-Forwarded-For`
string as throttle identity. Cloudflare and Caddy *append* to XFF rather than
stripping client entries, so an attacker-prepended value survives; varying the
leftmost value per request yields a fresh bucket, defeating the `login` 5/min cap.
No per-account lockout exists. Brute-force reachable, and **fully Cloudflare-
bypassed via the origin IP** (see D2).
*Fix:* set `NUM_PROXIES`, or switch throttle identity to the already-trusted
`CF-Connecting-IP`; add a per-account failed-login lockout.

### D1 · No automated database backups — HIGH, confirmed
`backend/scripts/backup-db.sh` exists but **nothing invokes it** (no timer, no
cron, no deploy call). The entire dataset is one sqlite file on the `backend_data`
volume. A disk failure, bad migration, or stray `docker volume rm` loses
everything — on an app whose whole purpose is aggregating data you can't re-fetch.
*Fix:* wire the script into a systemd timer; keep N daily copies off-volume.

### D2 · No host firewall; Cloudflare fully bypassable — HIGH, confirmed live
`compose.yaml:73-75` publishes `80/443` on all interfaces; no ufw/nftables filter
on the box. Verified: resolving the hostname to `65.21.185.210` directly serves
the app, bypassing Cloudflare's WAF/rate-limiting/DDoS edge entirely. Origin IP
leaks routinely (historical DNS, cert transparency). This is the multiplier under
A1 and A5 — the "protected by Cloudflare" assumption is currently false.
*Fix:* nftables/ufw allowing 80/443 only from Cloudflare's published ranges.

---

## Priority 2 — soon, lower blast radius

### A6 · `get_serializer_class` match-case bug leaks all users' PII — MEDIUM, confirmed
`accounts/views.py:261-267`
`case ("GET", wanted_pk) if wanted_pk is not None` is a **capture pattern**: it
rebinds `wanted_pk` to the requester's pk instead of comparing to the URL pk. So
every authenticated GET — list *and* detail — returns `UserFullReadSerializer`
(`email`, `is_staff`, `is_superuser`, timestamps) for all users, not the intended
minimal serializer. With open registration, any stranger can enumerate every
user's email.
*Fix:* compare explicitly (`case ("GET", pk) if pk == str(requester_pk)`), and
scope `UserViewSet.queryset` to the requester for non-admins.

### A7 · Django admin registers `User` with a plain `ModelAdmin` — MEDIUM, confirmed
`accounts/admin.py:5`
Not `UserAdmin`, so the change form renders `password` as a text input and saves
it **verbatim, unhashed**. A staff user "fixing" the password field stores a
plaintext credential that then fails `check_password`.
*Fix:* register with `django.contrib.auth.admin.UserAdmin` (or a subclass).

### A8 · Committed dev-bootstrap credential — MEDIUM (personal-hygiene HIGH), confirmed
`notif/config.py:72-73` contained a human-chosen bootstrap credential tied to the
developer account; the credential itself is deliberately not reproduced here.
It was committed while the repo was on GitHub. Prod has
`DEBUG=false` so the auto-create/resurrect path (`accounts/views.py:65-87`) is
**off live**; residual risk is repo exposure + password reuse elsewhere.
*Fix:* rotate the password out of your personal rotation; move the default to a
non-credential placeholder; add a startup assert `production ⇒ not DEBUG`.

### F1 · Native refresh token stored plaintext, backups enabled — MEDIUM, confirmed
`frontend/lib/services/refresh_cookie_store.dart:137-156`; no
`flutter_secure_storage`; Android `allowBackup` defaults true.
An `HttpOnly` refresh token is extracted and written as cleartext to
`SharedPreferences`; `adb backup` / cloud backup / rooted device yields a token
valid up to 72 h. `HttpOnly` is effectively downgraded on native.
*Fix:* keystore-backed secure storage; set `android:allowBackup="false"` +
`dataExtractionRules`.

### F2 · Web logout can silently fail to end the session — MEDIUM, confirmed
`frontend/lib/services/auth.dart:198-216`
`logout()` swallows the `/token/logout/` failure and its `finally` only clears
native cookies (no-op on web). Logout while offline → UI shows `AuthAnonymous`
but the browser keeps a valid `notif_refresh` cookie the server never revoked;
next launch silently re-auths. On a shared machine the user believes they logged
out. (Same theme as A3 — client-side "log out" without a server round-trip evicts
nothing.)
*Fix:* surface logout-request failure; don't present success unless the revoke
round-trip succeeded (or the cookie is provably cleared).

### F3 · 401-race can bounce a freshly logged-in user to login — MEDIUM, confirmed
`api_client.dart:307-323`, `auth.dart:114-120,145-170`
A parked refresh returning `null` on epoch mismatch is treated as failure by
`_refreshAccessTokenIfNeeded`, which calls `_authExpiredHandler`; that sets
`AuthExpired` whenever `jwt != null` — true if a fresh `login()` populated the
session in the same window. Narrow, but it overwrites a valid session.
*Fix:* thread the epoch through the expired-handler call, or have it no-op when
the current state is a fresh `AuthAuthenticated`.

### A9 · `StrategyViewSet` write/delete on shared/unowned strategies — MEDIUM, confirmed
`monitoring/views.py:69` — `IsAuthenticated` only; protection is queryset scoping
that includes globally-unowned (`link_set__isnull=True`) and co-linked
strategies, all mutable/deletable. Editing a shared strategy alters another
user's scraping config. Collapses to self-only if registration closes.
*Fix:* add object-level ownership perm; give Strategy a real owner.

### A10 · Password validation at registration runs without user context — LOW, confirmed
`accounts/serializers.py:54-55` calls `validate_password(password)` with no
`user`, so `UserAttributeSimilarityValidator` is a no-op on create — a user can
register with password == username/email. `change_password` and reset pass the
user correctly.
*Fix:* pass the (unsaved) user instance into `validate_password`.

### D3 · Deploy-day trap: legacy cron removal is a silent no-op under sudo — MEDIUM, confirmed
`deploy.sh:63-69` removes the old `*/5` entry via `crontab -l | … | crontab -`,
which operates on the *invoking* user's crontab. The legacy entry is in `luka`'s
crontab; the rest of `sync_host_config` is `sudo`-wrapped, so running the deploy
as root reads root's empty crontab and never removes it → both cron and the new
timer fire `run_due_tasks`. The app-level `MaintenanceLock` prevents corruption,
so this degrades to contention, but it's exactly the drift to watch.
*Mitigation:* run `deploy.sh` as `luka`; verify `crontab -l | grep run_due_tasks`
prints nothing afterward.

---

## Priority 3 — hardening / hygiene

- **D4 · Redeploy wipes the web root in place** (`frontend/entrypoint.sh`
  `rm -rf /web-dist/*` then `cp`; Caddy doesn't wait for the one-shot) → brief
  404/broken-asset window every deploy. No atomic swap. MEDIUM, confirmed.
- **D5 · No CPU/memory limits on any container** (`compose.yaml`); gunicorn
  `--workers 4` + lxml scraping on a small VPS can OOM the host and take Caddy
  with it. MEDIUM, confirmed.
- **D6 · Caddy sets no security headers on the SPA shell / static assets** (no
  `header` directive); the Flutter `index.html` gets no `nosniff` / `X-Frame` /
  CSP / HSTS — clickjacking + MIME-sniff surface unless CF injects them. MEDIUM.
- **D7 · `origin-certs` are an unprovisioned hard prerequisite** — missing
  `/etc/caddy/origin-certs/lcenzo.com.{pem,key}` makes *all* of Caddy fail to
  start, taking down the notif site too. MEDIUM, confirmed dependency.
- **D8 · Bad migration = downtime, no rollback** (`docker-entrypoint.sh:5`
  migrate on every start; `up -d` recreates backend) — compounds D1. MEDIUM.
- **D9 · Secrets visible via `docker inspect` / `/proc/<pid>/environ`**
  (`env_file`); acceptable single-admin, worth a conscious call vs compose
  secrets. MEDIUM.
- **Spoofable client IP in audit records** — `commons/network.py:6` takes leftmost
  XFF; poisons `RefreshSessionFamily.ip`, backup/client-event audit rows. LOW.
  (Behind CF, the trustworthy value is `CF-Connecting-IP`.) [backend L1 + authz F8]
- **Concurrent double-submit of one refresh token revokes the whole family**
  (`refresh_sessions.py:103-106`) — two tabs / retry-on-timeout logs the user out
  everywhere. Defensible, but an availability edge worth a conscious decision. LOW.
- **Unauthenticated writes to the ops event log** (`ClientEventView`, `AllowAny`)
  — scrubbed + 30/min throttled, but anonymous row injection + slow growth. LOW.
- **Public build-info disclosure** (`status_check` `AllowAny` → version/commit/env;
  confirmed live) + intentionally public OpenAPI schema. LOW/INFO. [deploy L6 + authz F9]
- **Debug `LogInterceptor` prints tokens + plaintext login password**
  (`api_client.dart:27-34`); `kDebugMode`-gated, not in release, but defeats the
  deliberate password masking. LOW.
- **No `sendTimeout`** (`api_client.dart:13-25`) and **cleartext
  `http://localhost:8000` API default** (`:8-11`) — bounded-everything gaps /
  footguns for new build targets. LOW.
- **Floating base-image tags** (`caddy:2`, `flutter:stable`), **single-stage
  backend ships the toolchain**, **`write-prod-env.sh` echoes 8 hex chars of the
  secret key**, **`Persistent=true` on a monotonic timer is a no-op** (missed runs
  are *not* caught up), **`collectstatic --clear` on every start** briefly empties
  static. LOW each. [deploy L1–L5]
- **`AUTH_HEADER_TYPES` includes `""`** (accepts schemeless `Authorization`),
  **no access-token revocation** (20 min prod exposure window; 48 h under DEBUG).
  INFO. [backend I1/I2]

---

## What the auditors agreed was done *right* at the audited commit (calibrated)

This subsection describes the historical refresh-token implementation, not the
opaque `DeviceSession` system on current master. At the audited commit, the
refresh-token subsystem was genuinely well built and shouldn't be touched
casually: family-based rotation with reuse detection, `select_for_update` +
atomic compare-and-set on `used_at`, whole-family revocation on both replay and
unknown-jti, no usable tokens at rest (only jti/family UUIDs persisted). CSRF
posture on the cookie flow is strong (`HttpOnly` + `SameSite=Lax` + `Secure` +
path-scoped + mandatory `X-Refresh-Request` custom header). Password-reset codes
are HMAC-SHA256 at rest with `constant_time_compare`, CSPRNG, single active code,
30 min TTL, DB-backed 5-attempt lock, and are enumeration-resistant. DRF is
closed-by-default (`IsAuthenticated` global, JWT-only) — every `AllowAny` is
deliberate, none accidental. The frontend auth state machine is *actually* sealed
(no nullable `isLoggedIn`), refresh is single-flight with an epoch guard, per-
request retry is bounded to one, no TLS bypass, and architecture tests enforce the
boundaries. Deploy: backend is internal-only, scheduled work holds a real DB
`MaintenanceLock` with bounded runtime, non-root containers, healthcheck, log
rotation, `chmod 600` gitignored secrets, random admin path, anti-spoof
`trusted_proxies_strict` + `CF-Connecting-IP`.

## Test-coverage gaps worth closing alongside fixes

These gaps were recorded on 2026-07-03 and are not assertions about current
coverage. At that point, `change_password` had zero tests and the
401→refresh→retry→expired path was entirely
untested (incl. F3 race and the single-flight/epoch guards); no logout test on
either platform; no router-guard test; throttling is disabled under tests so A5
has no regression guard; the `UNKNOWN_TOKEN` revocation branch and the
dev-bootstrap resurrection branch are uncovered; and there's no test asserting
tokens/passwords aren't logged.
