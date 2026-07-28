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
	Most original "what next" items have shipped — see `docs/CHANGELOG.md`. Still open:
	- External notification delivery (FCM/APNs, Telegram, Discord) — see "Push notifications" below.
	- APK build for personal use.
	- Investigate why `run_due_tasks --max-links 1` reported 0 considered on a freshly cron-updated VPS (Link count vs `scrape_disabled` state).
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
	Resolved: cron + `manage.py run_due_tasks` with per-link DB scheduling — no APScheduler, no Celery. Details in `docs/architecture/run_due_tasks.md`.

Current scraper limitations worth remembering:
	GeneralSelectorStrategy hash comparison is still fragile for dynamic content.
	Requests are still sequential within a single `run_due_tasks` invocation. Concurrency would be a real change, not a small one.
	Per-link rate limiting and exponential backoff exist now (DomainRateLimiter + scrape_failure_count). Strategies with multiple internal requests still need their own throttling discipline — the per-domain limiter only paces the top-level fetch.


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

## Pagination & Filtering — shipped

Documented in `docs/architecture/pagination.md`. Page-based on Links and Notifications, `?status=` / `?since=` filters, OrderingFilter with `-pk` tiebreaker, global `unread_count` in the paginated envelope.

---

## Product / Ops Backlog Discussion (added 2026-05-05)

### Domains and deploy surface

- Current shape: `notif.lcenzo.com` on Hetzner CX33 (Helsinki), Docker Compose (`notif-caddy-1` publishes 80/443, `notif-backend-1` internal 8000), Caddy + Let's Encrypt (DNS-01 via Cloudflare now that the host is Proxied). Cloudflare DNS, orange-cloud on `notif`. Not expected to change much — single-user-ish app, no growth pressure.
- Apex `lcenzo.com` + `www.lcenzo.com` repointed to the VPS, landing page + Caddy split prepared (pending merge — see `docs/CHANGELOG.md`). Wildcard `*.lcenzo.com` 404 was already wired and working.

### Cloudflare orange-cloud — migrated

Done. `notif.lcenzo.com` is Proxied. Caddyfile carries the CF IP allow-list with `trusted_proxies_strict` and `client_ip_headers CF-Connecting-IP`; Django side has `ALLOWED_HOSTS`, `CSRF_TRUSTED_ORIGINS`, `SECURE_PROXY_SSL_HEADER` set in production env. Possibly worth a follow-up:
- Decide whether `/api/*`, login, and password-reset routes should sit behind any CF rules / rate limits.
- Confirm cert renewal path is genuinely DNS-01 and not relying on a transient grey-cloud window.

### VPS agent

Subsumed by the "Agent harness integration" section at the bottom of this file. The narrow-perms ops agent is one of three job-shapes there (`ops`).

### Scraping scheduler — mostly shipped, residual work

Core (cron-driven `run_due_tasks` with per-link DB scheduling, per-domain rate limit, exponential backoff) is built and now wired in production (cron on `notif` updated 2026-05-07). Architecture details in `docs/architecture/run_due_tasks.md`. Still open:

- `run_due_tasks` first manual run on the VPS reported 0 due Links — investigate Link inventory / `scrape_disabled` state to confirm scrapes actually fire.
- XenForo threadmark monitoring: support selecting which tabs to watch (Threadmarks / Sidestory / Apocrypha / Informational).
- Jitter on `next_scrape_at` to avoid herd timing across many Links with the same interval.
- Conditional fetch via `If-Modified-Since` / `ETag` where the source supports it — avoid re-pulling unchanged content.
- Per-strategy throttling for strategies that issue multiple internal requests (the per-domain limiter only paces top-level fetches).

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

---

## Agent harness integration — design sketch (added 2026-05-07)

### Goal

Run an agent harness alongside the Notif backend on the VPS. First milestone: take one or more Notifications plus a free-text question, produce a written discussion / summary that the user can read in the FE and reference later. Later milestones: filter (per-Link salience deciding deliver/skip), investigate (multi-step research with web fetch), and ops (narrow-perms VPS babysitter — line 175–179 above is now subsumed by this section).

### Constraints

- **No Claude Code Max sub credentials inside the harness.** Harness env carries only console-issued keys: DeepSeek, OpenRouter, an OpenAI-side sub through its own harness if applicable. Anthropic-API key only if separately purchased and only for the harness, not the BE.
- The harness is **invoke-per-task**, not a long-running service. "Running alongside Notif" means co-located on the VPS, not co-resident in the same process.
- Notif BE remains source of truth for Links, Updates, Notifications. Agent **never writes** those tables. Agent output goes to a knowledge base, not the operational DB.

### Recommended shape — co-located worker (Shape A)

**New `agents/` Django app:**
- `AgentJob` model: `kind` (`filter` | `investigate` | `ops`), `payload` (JSONB — what the user asked, which Notifications/Links are in scope), `status` (`pending` | `running` | `ok` | `error`), `created_at`, `started_at`, `finished_at`, `output_ref` (KB git commit hash + path), `error_text`.
- DRF endpoints: `POST /api/v1/agent-jobs/` to enqueue, `GET /api/v1/agent-jobs/<id>/` to poll. FE buttons enqueue jobs ("ask agent about this notification", "summarize last week of <Link>", etc.).

**Worker (separate systemd unit `notif-agent-worker.service`):**
1. Polls/claims a `pending` AgentJob row (SELECT ... FOR UPDATE SKIP LOCKED, or a simple status-flip in a transaction).
2. Builds an **explicit briefing JSON** from the DB — only the fields the agent should see, never the raw schema. Drops it at `/var/lib/notif-agent/jobs/<id>/in.json`.
3. Invokes the harness CLI with the job dir as cwd. Non-Anthropic API keys passed via env. CPU/memory caps via `systemd-run`.
4. Harness writes Markdown output into the job dir; on success, also commits to a job-specific branch in the KB git repo.
5. Worker fast-forwards the branch into `main` of the KB repo, records the resulting commit hash + paths into `AgentJob.output_ref`, marks job done. On harness non-zero exit, marks `error` with stderr stored.

**Knowledge base:**
- Plain bare git repo at `/var/lib/notif-kb/`. Layout `kb/<topic>/<slug>.md`. Versioning is just git history — `git log` for an audit trail, `git show <hash>:<path>` to render a specific version.
- BE exposes a read-only endpoint, e.g. `GET /api/v1/kb/?path=<...>&ref=<hash>`, that shells `git show` against the bare repo and returns the Markdown body + commit metadata. FE renders with a "version" dropdown bound to recent commits touching that path.

**Sandboxing & access control:**
- Each job runs in its own scratch dir; harness can be wrapped in `firejail` / `bwrap` / a per-job Docker container with the job dir + KB repo as the only writable mounts.
- Harness has **no direct DB access**. The briefing JSON is its world. If a job needs richer data mid-run, the worker exposes a thin internal HTTP endpoint with a per-job service token; the harness calls it via a tool. This keeps the agent's view explicit and replayable — every job's `in.json` is the auditable input.

### Alternative shapes considered

- **Shape B — sidecar HTTP service wrapping the harness.** Tiny FastAPI service on the VPS, BE calls it for sync-ish work (filter), enqueues for async (investigate). Adds a service to deploy/monitor for no clear win at this scale — the AgentJob DB row already gives BE→worker decoupling. Revisit if filter-style sync calls become hot.
- **Shape C — BE invokes harness inline via subprocess from a request handler.** Simplest deploy, but tight coupling, no audit trail, harness latency starves gunicorn workers, no clean place to put per-job sandboxing. Reject.

### First milestone (build order)

1. `agents/` app with `AgentJob` model + create/poll endpoints. **No worker yet.**
2. Worker stub that flips jobs to `ok` with a hard-coded "Lorem ipsum" summary so the FE plumbing (button → enqueue → poll → render KB doc) can be built and demoed end-to-end.
3. Wire in the actual harness CLI. Start with one `kind` (probably `investigate` against a single Notification) before adding `filter` and `ops`.
4. Add KB read endpoint + version dropdown in FE.

### Open questions

- Which non-Anthropic harness lands first? OpenAI Codex through its own harness is one option, a generic harness over OpenRouter is another. Short bake-off after milestone 1.
- External fetching from inside the agent: same hygiene as the scraper. Prefer fxtwitter/RSS/structured endpoints; ad-hoc fetch only when no structured source exists.
- Rate-limit budget: probably **separate** buckets for scraper vs agent. Different workloads, different blast radii.
- KB visibility: global for v1 (Notif is single-user today). Add per-user scoping when/if that changes.
- Concurrency: how many worker processes? Start with one. Concurrency adds correctness questions (locking, KB merge conflicts) before the workload demands it.

---

## Best Rust Candidates In This Codebase

Do not Rustify the Django app wholesale. Django should stay the source of truth for auth, ORM, migrations, API, admin, scheduling, and product state. Rust fits best either below the current scraper strategy boundary as deterministic parsing/diffing code, or beside Django as an isolated worker process with an explicit JSON contract.

### Scrape parsing and diff core

The strongest first experiment is a small `notif_scrape_core` Rust crate exposed to Python through PyO3/maturin. Keep network fetches and DB writes in Python, but move pure transforms behind a stable API:

- `selector_digests(html, selectors) -> dict[str, list[str]]`
- `html_to_readable_text(html) -> str`
- `normalize_feed(xml_bytes) -> list[entry]`
- `merge_seen_entry_hashes(current, previous, max_seen) -> list[str]`

This maps to the current `monitoring.strategies` contract: strategies emit normalized `ScrapedUpdate` rows plus optional comparison state. It is low-risk because fixtures can pin behavior before and after the port.

### Separate scraper or collector worker

If scraping grows into concurrent fetching, conditional requests, source-specific cooldowns, or heavier HTML parsing, Rust could own a worker that receives due scrape jobs as JSON and returns normalized updates plus comparison-state patches. Django would still own `Link`, `Update`, `Notification`, scheduling, backoff, and persistence.

This is a better fit than embedding large async scraping logic inside the Django request/management-command process. It also makes timeouts, memory limits, and crash recovery easier to reason about.

### Search later

Start any search endpoint with SQLite FTS or Postgres search. If local search becomes large or ranking-heavy, a Rust/Tantivy sidecar is plausible later. Do not start there.

### Agent worker supervisor

For the planned agent harness, keep `AgentJob` models and DRF endpoints in Django. Rust could be useful as the worker/sandbox wrapper that claims jobs, writes briefing JSON, invokes the harness, enforces CPU/memory/time limits, and records output references.

Rust should not own the agent product logic or write directly to Notif's operational tables.

### Big archive/import parsing

For X/Twitter profile export or other large JSON/archive imports, Rust is a reasonable candidate if Python parsing becomes slow or memory-heavy. Live X monitoring should be prototyped in Python first unless a stable structured source exists.

### Poor Rust candidates

- Push notification product state and `DeliveryAttempt` modeling.
- Django auth, refresh-token rotation, permissions, serializers, admin, migrations, and API views.
- F-Droid/APK release plumbing.
- Flutter UI state and normal API DTO parsing.

### Recommended build order

1. Add a tiny Rust crate for one deterministic scraper helper, probably `html_to_readable_text` or selector digest extraction.
2. Expose it with PyO3/maturin and keep a Python fallback while the packaging settles.
3. Run existing scraper fixtures against both implementations until behavior is pinned.
4. Only then consider moving larger feed normalization or worker boundaries.

---

## Cleanup TODO (added 2026-05-14)

Ordered roughly by impact within each section.

### Backend

**Medium impact**
- Squash `monitoring` migrations — 13 migrations + 1 merge → 1-2 squashed
- Squash `accounts` migrations — 8 → 3
- Split `monitoring/strategies.py` (1112 lines) into domain modules
- Unify throttle-test-gating: `PasswordResetRequestView` / `PasswordResetConfirmView` reimplement `get_throttles()` instead of using `TokenThrottleMixin`
- Extract `run_due_tasks.py` helper functions to `ops/maintenance.py`

**Low impact / housekeeping**
- Remove `misc/secrets.json` + `misc/*.ipynb`
- Delete dead `IsOwner` permission — subsumed by `IsOwnerOrAdmin`, never imported
- Remove unused `TriggerScrapeAllResponseSerializer`
- Remove unused `lxml` dependency
- Remove unused `Notification.Status.DISMISSED`
- `UserMinimalReadSerializer` list view missing `name` / `email`
- Remove unused Faker providers (`bank`, `company`) from `commons/utils.py`
- TYPE_CHECKING boilerplate in 5 files

### Frontend

**High impact**
- Split `homescreen.dart` (3152 lines) — 30+ private widget classes, pagination, dialogs
- Split `data.dart` (1306 lines) — separate `LinkService` / `NotificationService`, extract pure utilities
- Gate `auth_texture_tuner.dart` (820 lines) with conditional import — ships in release builds

**Medium impact**
- Shared `AuthFormLayout` widget — login/register share near-identical dual (framed/glass) form implementations
- `PaginatedServiceMixin` — `LinkService.goToPage()` / `NotificationService.goToPage()` share ~80% identical code
- Centralize `AuthCardStyle` branching (~20 sites)
- Merge `AuthBackdropColors` / `_AuthBackdropPalette`

**Low impact / housekeeping**
- Remove unused `screens/shared.dart` barrel export
- Inline `_KVText` (kv.dart), `_StaticText` (about.dart), `_AccountTextField` (account.dart)
- Extract pagination window algorithm from `homescreen.dart` to a pure function (test duplicates it)
- Test coverage: `AuthService`, `LinkService`, `NotificationService`, `OpsService`, `account.dart`, `forgot_password.dart`, `reset_password.dart`
