Flutter packages to look into:
- Nice style
	https://pub.dev/packages/fluent_ui/

- Cool addition, nice animation
	https://github.com/aagarwal1012/Liquid-Pull-To-Refresh

- Premade settings widgets
	https://github.com/codegrue/card_settings

- Log in animation:
	https://github.com/GeekyAnts/flutter-login-home-animation/tree/master

- Flushbar/bottom popup
	https://github.com/AndreHaueisen/flushbar



What next:
	Create the UI for Link CRUD, and state management.
	Create a notification model, figure out storage
	Figure out how to send notifications
	Dockerize backend, try creating a docker compose setup for the server. ✓ (PR #24)
	Try deploying:
		Django has a production checklist ✓
		IDK about Flutter, just flags for builds?
		nginx? ✓ (Caddy instead of nginx — see Caddyfile + deploy.md)
	Figure out scraping on a schedule. Celery, cron jobs, or whatever. ✓ (manage.py scrape + cron)
Push notifications:
	Notification model currently tracks in-app read/dismiss state only.
	When adding push (e.g. FCM), separate delivery tracking from read state —
	either a DeliveryAttempt table (channel, status, sent_at, error) per
	Notification, or at minimum push_sent_at/push_failed_at fields.
	A single notification may have multiple deliveries (push + email + in-app).

	Delivery channels (two approaches):
	Option A — FCM/APNs (native push):
	Standard mobile push via Firebase Cloud Messaging and Apple Push
	Notification service. Best for app-first users who want OS-level
	notifications. Requires FCM setup, APNs certs, and the app to be
	running (or at least registered for push). Works without any
	third-party messaging apps.

	Option B — Telegram/Discord as delivery wire:
	The backend POSTs directly to the Telegram Bot API or Discord webhook
	when a Notification is created. No push infrastructure, no Hermes
	required. Advantages: no Google/Apple dependency, no cert management,
	user already lives in these apps, one-tap-to-read (link opens in
	browser). Trade-off: requires the user to have Telegram/Discord and
	the bot to be running.

	Per-source opt-in:
	Users choose which delivery channel(s) they want per monitored source
	(not globally). A Link gets a delivery_channels JSON field — ["telegram",
	"discord", "in_app"]. Default: in_app only. User sets this when adding
	or editing a link. Different sources can go to different channels.

	LLM filtering (future idea):
	Not every update is worth a push. A user could attach free-text
	instructions to a Link ("only notify me about posts by Scott Alexander,
	not open threads"). After scraping, a cheap LLM call checks the update
	title/description against the user's filter instructions and decides
	whether to deliver. This replaces brittle keyword matching with semantic
	understanding. Trade-off: latency + cost per update. Worth it for
	high-volume feeds where most updates are noise.

	DeliveryAttempt model (when we get there):
	Track each attempted delivery per channel. Fields: notification (FK),
	channel (telegram|discord|email|in_app), status (pending|sent|failed|
	bounced), sent_at, error_message. Enables retry logic and per-channel
	success rate tracking.

Backend scraping direction:
	Keep scheduling simple at first: management command + OS cron / scheduled task.
	If per-link schedules or in-process scheduling become necessary, prefer APScheduler
	before jumping to Celery/Beat/Redis complexity.

Current scraper limitations worth remembering:
	GeneralSelectorStrategy hash comparison is still fragile for dynamic content.
	Requests are still sequential and there is no retry/backoff layer yet.
	Rate limiting now exists, but it only spaces top-level link scrapes; strategies
	with multiple internal requests still need their own throttling discipline.


---

## Scraping Ideas & Workarounds (from 2026-04-11 session)

### RSS for XenForo forums (SB/SV/QQ)
- `https://forums.spacebattles.com/threads/foo.123456/threadmarks.rss` -- structured XML for threadmarks
- Would massively simplify `SBSVThreadmarksStrategy` -- use `feedparser` library instead of HTML parsing
- RSS does NOT cover user profiles or alerts, only thread content

### httpx for async
- Lightweight async HTTP client, drop-in-ish replacement for `requests`
- Better than Scrapy for this project's scale -- use with a per-domain semaphore for rate limiting
- Enables concurrent fetching without the full Scrapy framework overhead

### fxtwitter.com for X/Twitter
- Replace `x.com` with `fxtwitter.com` in URLs -- server-side rendered, no JS needed
- API endpoint: `https://api.fxtwitter.com/username/status/123` returns structured JSON
- Also: vxtwitter.com, girlcockx.com (same service, different domains)
- Free, no API key, volunteer-run -- risk of going down but fine for personal use
- Test whether `https://api.fxtwitter.com/username` gives recent tweets for profile monitoring

### SubscribeStar
- Target site for monitoring (similar to Kemono use case -- creator updates)
- Needs investigation: is it server-rendered? Does it have RSS? API?

### Cloudflare bypass options (if sites start blocking plain requests)
- **curl_cffi** -- impersonates browser TLS fingerprints, drop-in for `requests`, lightweight
- **cloudscraper** -- specifically for Cloudflare challenges, wraps `requests`, may lag behind updates
- **Playwright / Selenium** -- full headless browser, heaviest but most reliable
- **FlareSolverr** -- self-hosted proxy that solves Cloudflare via headless browser, Dockerizable
- **undetected-chromedriver** -- patched ChromeDriver, less maintained than Playwright
- Not needed currently -- forum targets (SB, SV, QQ) don't use aggressive Cloudflare

---

## Pagination & Filtering (added 2026-05-04)

### Architecture

- **Notifications** use page-based navigation (page numbers at bottom when `totalPages > 1`). Each page fetch replaces the list entirely — no infinite scroll / "load more" append model. `NotificationPagination` page_size=50, max_page_size=200.
- **Links** use the same page-based model. `LinkPagination` page_size=100, max_page_size=500.
- Sorting is delegated to the backend via DRF's `OrderingFilter`; the FE sends `?ordering=<field>` and the server returns correctly ordered pages. Sort enums (`LinkSort`, `NotifSort`) include tiebreaker fields (`-pk`) to keep page boundaries deterministic.

### Why not continuous scroll?

Continuous scroll (infinite scroll / "load more") was explicitly rejected for this app. Reasons:

1. **Dedup complexity** — pages shift when new items land (a new notification on page 1 pushes the old page 1's last item to page 2). Load-more-then-dedup creates visual glitches where items appear, disappear, or reorder.
2. **Navigation loss** — you can't link to or return to "page 3 of notifications." With page numbers, the current position is explicit and recoverable.
3. **Unread count accuracy** — the server reports a global `unread_count` independent of the current page filter. Continuous scroll would make the relationship between visible items and unread count confusing ("UNREAD 0" with unread items on unloaded pages).
4. **Power-user ergonomics** — for an app meant to handle hundreds of sources and thousands of notifications, scanning by page is faster than endless scrolling.

### Filtering

Status filtering (`?status=unread`) and time-based filtering (`?since=<ISO datetime>`) are supported on the notifications endpoint. These filters scope the queryset before pagination, so page counts and unread counts reflect the filtered set.

Adding more filter dimensions (by link/source, by strategy type, text search) would follow the same pattern: query param → `get_queryset().filter(...)` → paginated response. The `unread_count` field in the paginated envelope is computed independently of any `?status=` filter — it always represents the user's global unread total — so the FE badge stays accurate regardless of what page/filter the user is viewing.

---

## Product / Ops Backlog Discussion (added 2026-05-05)

### Domains and deploy surface

- Infra snapshot from 2026-05-05:
  - App domain: `notif.lcenzo.com`.
  - VPS: Hetzner CX33 in Helsinki.
  - DNS: Cloudflare.
  - Cloudflare mode for `notif.lcenzo.com`: grey-cloud / DNS-only.
  - Public firewall intent: SSH, HTTP, HTTPS, and ICMP.
  - Deployment shape from VPS inspection: Docker Compose-style containers, with `notif-caddy-1` publishing ports 80/443 and `notif-backend-1` internal on port 8000.
  - Caddy certificate mode from VPS inspection: Let's Encrypt public certificate managed by Caddy under `/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/`.
- Add a real `lcenzo.com` page even if it is tiny, so the apex domain does not resolve to an empty or parking-like destination.
- Add a proper not-found / setup-not-available page for routes or hostnames that are not configured. This should make wildcard/CNAME state less confusing while DNS is still being cleaned up.
- Keep this as deployment polish, not core app scope, unless DNS or routing blocks users from reaching the app.

### Cloudflare orange-cloud decision

- Orange-clouding `notif.lcenzo.com` is probably useful eventually for DDoS shielding, WAF/rules, hiding the origin IP, and edge caching of static frontend assets.
- Prep needed before switching:
  - Ensure Django has correct `ALLOWED_HOSTS`, `CSRF_TRUSTED_ORIGINS`, `SECURE_PROXY_SSL_HEADER`, and Caddy trusted proxy settings.
  - Decide certificate path: temporary grey-cloud for Let's Encrypt issuance, Cloudflare Origin Certificate, or DNS-01 via a Caddy Cloudflare DNS module.
  - Confirm Caddy logs real client IP from `CF-Connecting-IP` and Cloudflare IP ranges are current.
  - Keep API paths uncached unless a specific endpoint is deliberately cacheable.
  - Decide whether Cloudflare security rules can block admin/login abuse without breaking mobile/web clients.
- Unknowns to confirm before changing DNS mode:
  - Whether to keep using Let's Encrypt after orange-clouding, or switch to Cloudflare Origin Certificate / DNS-01.
  - Exact Cloudflare cache/WAF rules for `/api/*`, login, password reset, and admin routes.
  - Whether ICMP should remain publicly allowed for diagnostics.

### VPS agent

- Investigate a small "Hermes agent" on the VPS with intentionally narrow permissions.
- Define the exact allowed operations before implementation: likely health checks, triggering safe maintenance commands, reading limited status, and reporting logs. Avoid broad shell access.
- Any agent should have explicit timeouts, command allowlists, and audit logging.

### Scraping scheduler

- Prefer one general backend command/entrypoint that checks all due work rather than a cron job that directly scrapes every source.
- Cron can run every 5 minutes and call the Django service/command; Django decides what is due:
  - scheduled scrapes per link/source
  - cleanup of expired password reset codes
  - future maintenance tasks
- Per-source schedules should be configurable. Some SV/SB/QQ threads can be checked daily; high-interest threads can be checked every 5 minutes.
- XenForo threadmark monitoring should support selecting which tabs/categories to watch, such as Threadmarks, Sidestory, Apocrypha, Informational, etc.
- The scheduler should be a good network citizen: per-domain rate limits, jitter, backoff on failures, user-agent/contact clarity where appropriate, and no repeated requests for unchanged work when cache validators or timestamps are available.
- Keep CPU cost bounded: avoid browser automation unless a site requires it, prefer RSS/structured endpoints where available, and cap concurrent work.

### Backend maintenance command design

- First implementation should stay boring: a Django management command called by cron/systemd timer, not Celery/Redis.
- Proposed command: `python manage.py run_due_tasks`.
- Responsibilities:
  - Acquire a lock so two runs cannot overlap.
  - Clean expired/locked password reset codes.
  - Select scrape jobs that are due.
  - Run a bounded number of scrapes with per-domain rate limiting.
  - Record enough output for cron logs and debugging.
- Scheduling state should live in the database, not in cron:
  - link-level interval, such as 5 minutes, hourly, daily
  - `next_scrape_at`
  - last success/failure timestamps
  - consecutive failure count
  - optional disabled/backoff state
- Cron should only express cadence: run the maintenance command every 5 minutes. It should not know which links exist or which are due.
- Keep the first version single-process and sequential unless runtime becomes a real problem. Concurrency adds correctness and anti-blocking complexity before the app needs it.
- Add explicit limits from the start:
  - max links per run
  - max runtime
  - per-domain delay
  - failure backoff cap
  - stale lock expiry
- Testing should cover:
  - due vs not-due link selection
  - lock prevents overlap
  - expired password reset code cleanup
  - scrape success schedules the next run
  - scrape failure backs off and does not loop forever
  - command exits cleanly and prints a useful summary

### X scraping

- X/Twitter scraping still needs investigation. The goal is reliable monitoring without hitting everything every run.
- First pass should identify available low-cost sources: official API feasibility, RSS-like mirrors, fxtwitter/vxtwitter-style structured endpoints, or browser automation only as a last resort.
- Blocking risk should be treated as part of the design, not an afterthought: rate limits, backoff, source-specific cooldowns, and graceful degradation matter.

### Email and account flows

- A general email system is not required for the core app, but it enables a conventional forgot-password flow and account lifecycle emails.
- Registration email is worth considering:
  - Welcome/confirmation email if accounts are public-facing.
  - Verification email only if account abuse or deliverability matters.
  - No email if this stays single-user/private and account friction is undesirable.
- Forgot password should avoid unnecessary screens. A better flow:
  - Screen 1: request reset email.
  - Screen 2: enter 6-digit code only.
  - Screen 3: enter and confirm the new password.
- Rationale: do not ask the user to spend attention typing a new password until the code is known to be valid.

### Notification semantics and home screen

- The `[t]` value on the home screen probably should not mean "time scraped" if a better user-facing timestamp exists.
- Prefer published time when the source exposes it; fall back to scraped/discovered time when publication time is unavailable.
- Imported historical notifications may need special handling or sorting so the home screen does not feel like a mass import dump.
- Home screen sorting deserves a first-class design pass: newest published, newest discovered, unread first, source grouping, or source priority may all be useful.

### Desktop notification interaction

- On desktop web:
  - Middle click on a notification should open the target/details page in a new tab, matching normal web expectations.
  - Left click should expand the notification inline rather than immediately navigating.
  - Expanded notifications should have a bounded height with an internal scrollbar if the content is long.
- This implies notification rows/cards need separate interaction zones or event handling for primary click vs auxiliary click.

### Home screen pagination polish

- The page buttons on the home screen are visually inconsistent with the rest of the app.
- They also sit too close to the bottom of the viewport while leaving too much gap above.
- Fix spacing so the pager either has balanced vertical spacing or deliberately attaches closer to the table/list.
