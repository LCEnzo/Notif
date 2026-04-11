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
	Dockerize backend, try creating a docker compose setup for the server.
	Try deploying:
		Django has a production checklist
		IDK about Flutter, just flags for builds?
		ngix?
	Figure out scraping on a schedule. Celery, cron jobs, or whatever.
	Push notifications:
		Notification model currently tracks in-app read/dismiss state only.
		When adding push (e.g. FCM), separate delivery tracking from read state —
		either a DeliveryAttempt table (channel, status, sent_at, error) per
		Notification, or at minimum push_sent_at/push_failed_at fields.
		A single notification may have multiple deliveries (push + email + in-app).


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