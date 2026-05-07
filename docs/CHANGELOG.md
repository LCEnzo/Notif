# CHANGELOG

A coarse timeline of what's shipped in Notif. Date anchors are approximate — they reflect when the work appears in notes / commits, not exact merge dates.

## 2026-05

- **Apex landing page (`lcenzo.com`)** (2026-05-07, pending merge + deploy). Repointed apex DNS in Cloudflare from Porkbun's L.INK biolink (44.230.85.241 / 52.33.207.7) to the Hetzner VPS. Caddyfile split: `lcenzo.com` and `www.lcenzo.com` serve `deploy/fallback/index.html` for `/` and fall through to `not-found.html` (404) for any other path; `*.lcenzo.com` continues to serve the styled 404 unchanged.
- **Production cron migrated to `run_due_tasks` (2026-05-07).** Replaced the legacy `*/5 * * * * ... python manage.py scrape` entry on `notif` with `python manage.py run_due_tasks`. Per-link scheduling, exponential backoff, password-reset cleanup, and `SystemEvent` audit are now actually running in prod.
- **Production hardening, Cloudflare orange-cloud migration.** `notif.lcenzo.com` is now Proxied on Cloudflare. Caddy carries the full CF IP allow-list, `trusted_proxies_strict`, `client_ip_headers CF-Connecting-IP`. Django has `ALLOWED_HOSTS`, `CSRF_TRUSTED_ORIGINS`, `SECURE_PROXY_SSL_HEADER` set in the production env. (Caddyfile, `backend/notif/settings.py`.)
- **Pagination + filtering shipped** as designed: page-based on Links and Notifications, `?status=` and `?since=` filters, OrderingFilter with `-pk` tiebreaker, global `unread_count` in the paginated envelope. See `docs/architecture/pagination.md`.

## 2026-04

- **Scheduled maintenance command.** `python manage.py run_due_tasks`: per-link scrape intervals, exponential backoff capped at 24h, max-runtime / max-links bounds, single-process lock, password-reset cleanup, `SystemEvent` audit log. See `docs/architecture/run_due_tasks.md`.
- **Per-link scheduling fields** added to `Link`: `scrape_interval_minutes`, `next_scrape_at`, `scrape_disabled`, `scrape_failure_count`, `last_scrape_error`. Migration `0013_link_last_scrape_error_link_next_scrape_at_and_more`.
- **`DomainRateLimiter`** for per-domain pacing of scrape requests.
- **`SystemEvent` + `MaintenanceLock`** in a new `ops` app, plus `SystemEventPagination` view.

## Earlier (rough order)

- **Backend deployed** via Docker Compose on Hetzner CX33 (Helsinki). Caddy publishes 80/443, `notif-backend-1` internal on 8000.
- **Caddy + Let's Encrypt** for TLS (now operating behind Cloudflare proxy).
- **Notification + Update split.** `Update` is the scraped item; `Notification` is delivery state for the user (`unread`/`read`/`dismissed`, `read_at`).
- **Link CRUD** — model + DRF viewset + Flutter UI.
- **Auth + accounts** — JWT, password reset codes (TTL + attempt cap).
- **Initial scrape pipeline** — strategies + `manage.py scrape`.

---

## Not shipped (still in NOTES.md)

For context — what's on the backlog, *not* in the codebase yet:

- External delivery channels: FCM/APNs, Telegram, Discord.
- `DeliveryAttempt` model.
- Per-Link `delivery_channels` opt-in.
- LLM filtering of updates against per-Link free-text rules.
- APK build for personal use.
- Forgot-password 3-screen flow.
- XenForo tab selection (Threadmarks / Sidestory / Apocrypha / Informational).
- Conditional fetch (If-Modified-Since / ETag) and jitter on the scheduler.
- X / Twitter scraping (fxtwitter / vxtwitter as fetch wire).
- SubscribeStar investigation.
- Home screen sort/filter design pass, desktop click-handling polish, pager spacing.
- Agent harness integration (see "Agent harness integration" in NOTES.md).
