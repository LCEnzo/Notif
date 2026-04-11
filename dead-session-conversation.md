# Dead Remote Session — 2026-04-11

Session ID: `57c639b1-ca54-4f44-a7a8-a1beae9d17a8`
Worktree: `bridge-cse_01AacmqtqAgM7uTch5CATkWH`
Died after: "Server unreachable for 11 minutes"
Model: Opus (via remote control, worktree spawn mode)

---

## Conversation Summary

### 1. Initial check-in

User greeted Opus, confirmed it was in a worktree on branch `worktree-bridge-cse_01AacmqtqAgM7uTch5CATkWH`, clean working tree.

### 2. Scraping & X API state

User asked about the state of page parsing, X scraping, and what's needed to check a few profiles 3x/day.

**Findings:**
- 4 scraping strategies exist (forum threadmarks, QQ alerts, Kemono favorites, generic CSS selector). All BeautifulSoup + requests, pure HTML, no JS rendering.
- Zero Twitter/X integration exists.
- 3 options for X: Official API ($200/month basic tier), direct scraping (impractical — JS SPA, anti-bot), third-party services ($10-50/month, structured data).
- No scheduled scraping exists yet — strategies are a library that nothing invokes.

### 3. Other approaches & current weaknesses

User asked how bad the current approach is and what alternatives exist.

**Assessment:** Current approach is fine for server-rendered forums. Weaknesses:
- `_fetch_url_content()` has no User-Agent (except QQ), no timeout, no retries
- `GeneralSelectorStrategy` hash comparison is fragile (dynamic content = false positives)
- No rate limiting or request pooling
- No async — sequential blocking

**Alternatives discussed:**
| Approach | Trade-off |
|---|---|
| RSS feeds | SB/SV/QQ are XenForo — have RSS for threads/threadmarks. Structured XML, no HTML parsing. |
| XenForo API | Structured JSON, needs API keys from forum admins. |
| Playwright/Selenium | Headless browser for JS-rendered sites. Heavy, slow, resource-hungry. |
| Scrapy | Full framework — retries, rate limiting, pipelines. Big migration, overkill for MVP. |
| httpx (async) | Drop-in-ish replacement for requests with async support. |

### 4. AdGuard DNS, rate limiting, RSS, fxtwitter, SubscribeStar

- **AdGuard DNS**: Won't help — scraping never loads ad resources in the first place.
- **Rate limiting**: Already noted in README TODOs and strategies.py line 4-5.
- **RSS for threadmarks**: XenForo supports `threads/foo.123456/threadmarks.rss`. Would simplify `SBSVThreadmarksStrategy`. No RSS for user profiles though.
- **Scrapy downsides**: Heavy framework, steep learning curve, opinionated architecture.
- **fxtwitter.com / girlcockx.com**: Noted as X workaround options.
- **SubscribeStar**: Noted as a scraping target.

### 5. BE MVP gaps & architecture decisions

- **Update vs Notification separation**: Yes, separate models. `Update` = what was scraped, `Notification` = delivery/read state per user.
- **Push notifications**: Polling every 15 mins is fine for MVP. FCM later if needed.
- **Scheduling**: Spectrum from management command + OS cron (simplest) to Celery + Beat + Redis (heaviest). Recommendation: start with management command, graduate to APScheduler.
- **Per-link scheduling**: Should be configurable per profile/thread/link.
- **Python Result type**: User wants Rust-style `Result<T, E>`. Roll our own — small, no dependencies.

### 6. Code assessment

- Links & strategies (models + API): Done. CRUD works, permissions work, tests pass.
- Parsing strategies: Partially done — General and SBSV tested, QQ and Kemono untested.
- 16 tests, all pass. Missing coverage: QQ/Kemono, error paths, `can_scrape_url` methods.
- Nothing calls `strategy.scrape()` yet — no orchestration code.

### 7. Plan created & Phase 1 started

A Plan subagent designed a 5-phase MVP plan (see `mvp-plan.md`).
An Explore subagent examined the scraping and API state.

The session created `backend/commons/result.py` (Phase 1) and was about to update `strategies.py` to use it when the connection died.

---

## Memories saved by the dead session

The session saved several memories (now in `~/.claude/projects/C--Users-LCEnzo-Notif---Copy/memory/`):
- Cloudflare workarounds (reference)
- Scraping ideas: RSS, httpx async, fxtwitter, SubscribeStar, rate limiting (reference)
- Project overview and MVP gaps (project)
- Per-link scheduling and notification separation (project)
