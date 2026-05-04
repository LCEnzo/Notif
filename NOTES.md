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