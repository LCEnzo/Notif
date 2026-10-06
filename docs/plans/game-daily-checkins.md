# Plan: game daily check-ins (HoYoLAB, SKPort)

Status: **proposal, not implemented** · Date: 2026-10-06 · Source: the "Game Daily Check-ins" section of the local, gitignored `TODO.md`

## Goal

Notif claims the daily web check-in reward for Genshin Impact (HoYoLAB) and Arknights: Endfield (SKPort) on a schedule, records one result per account per day, raises a Notification when a run needs a human, and shows a small status screen with the last run, its outcome, the reward, the monthly count and the next run. Code redemption, the "make-up" sign-ins and other HoYoLAB features are out of scope.

## Verified facts per platform

Every load-bearing fact cites prior-art source code or an issue thread. *Inference* marks my own reasoning, and percentages are my confidence.

### HoYoLAB (overseas)

| Item | Fact | Source |
|---|---|---|
| Genshin base | `https://sg-hk4e-api.hoyolab.com/event/sol/` with `sign` (POST), `info` (GET) and `home` (GET), plus the query `act_id=e202102251931481&lang=en-us` | `seriaati/genshin.py` (formerly thesadru) `genshin/client/routes.py` `REWARD_URL`; `torikushiii/hoyolab-auto` `hoyolab-modules/genshin/index.js` |
| Other games | HSR `sg-public-api.hoyolab.com/event/luna/hkrpg/os` `e202303301540311`; ZZZ `.../event/luna/zzz/os` `e202406031448091`; HI3 `.../event/mani` `e202110291205111`; ToT `.../event/luna/nxx/os` `e202202281857121` | `genshin/client/routes.py`; Croissant `data/.../dao/CheckInService.kt` |
| Body | none, since `act_id` goes in the query. Croissant also sends JSON `{"act_id": ...}`; both work | `genshin/client/components/daily.py`; Croissant `GenshinImpactCheckInService.kt` |
| Headers | `Cookie`, `Referer: https://act.hoyolab.com/`, a desktop Chrome UA and `x-rpc-signgame: hk4e` (or `hkrpg`/`zzz`/`bh3`/`nxx`). hoyolab-auto adds `x-rpc-app_version: 1.5.0` and `x-rpc-client_type: 5`. **No DS header overseas**; only the CN branch signs | `daily.py` `request_daily_reward`; `hoyolab-auto` `gots/hoyolab/index.js` |
| Status shape | `{retcode, message, data}`; `info` returns `data.is_sign`, `data.total_sign_day`, `data.today`; `home` returns `data.awards[] {name, cnt, icon}` | `genshin/models/genshin/daily.py`; `hoyolab-auto` `check-in.js` |
| Codes | `0` ok; `-5003` already claimed; `-100`/`10001`/`-1071` invalid cookie; `-10002` no game account; `-1004`/`-500004`/`-110` too frequent | `genshin/errors.py` `_errors`; Croissant `domain/.../HoYoLABRetCode.kt` |
| Captcha | the retcode is `0`, but `data` (or `data.gt_result`) has `risk_code != 0` with a `gt` and a `challenge`, so the claim **did not happen** | `genshin/errors.py` `check_for_geetest`; genshin.py #131 ("phantom reward collection") |
| Day boundary | 00:00 UTC+8 (16:00 UTC) for every overseas server | `genshin/models/genshin/daily.py` computes `missed_rewards` with `CN_TIMEZONE` (*inference*, 85%) |

The auth cookies are `ltuid_v2` and `ltoken_v2`, with `ltmid_v2` optional; some endpoints need it (genshin.py #151). Luka obtains them once from browser DevTools (Application → Cookies → hoyolab.com) while logged in. The cookies are HttpOnly, so JS extraction no longer works (canaria3406/hoyolab-auto-sign #26).

Lifetime is not documented. Changing the password or logging out invalidates the cookies (hoyolab-auto-sign #26; genshin.py #151). Users report "expired after few months" (hoyolab-auto-sign #62, 2025-01). The hoyolab-auto maintainer says check-in cookies "can last around a year" while the redemption token (`cookie_token_v2`) dies in days to weeks (hoyolab-auto #143, 2026-09/10). Automated refresh needs an `stoken`: `getBySToken` mints a fresh `ltoken_v2` from one (`genshin/client/manager/cookie.py` `fetch_cookie_with_stoken_v2`). Browsers no longer expose `stoken`, and the older refresh endpoint now returns `-707` (hoyolab-auto PR #136, merged 2026-09-13). An `stoken` comes only from an app-password login with a geetest. **Verdict: expiry means a manual re-paste.**

### SKPort (Endfield)

| Item | Fact | Source |
|---|---|---|
| Status | `GET https://zonai.skport.com/web/v1/game/endfield/attendance` returns `data.hasToday` | `Areha11Fz/ArknightsEndfieldAutoCheckIn` `EndfieldAutoCheckIn.js`; `AixLnyt/skport-api-docs` `README_EN.md` |
| Claim | `POST` to the same URL with **no body**, signed with body `""`. Success is `code: 0` with `data.awardIds[]` and `data.resourceInfoMap{id: {name, count, icon}}` | Areha `EndfieldAutoCheckIn.js`; `canaria3406/skport-auto-sign` `src/main-discord.gs` |
| Role | header `sk-game-role: 3_{roleId}_{serverId}`; server `2` = Asia, `3` = Americas/Europe; auto-detect via `GET zonai.skport.com/api/v1/game/player/binding` | canaria `README.md`; Areha `fetchSkGameRole` |
| Headers | `cred`, `sign`, `timestamp` (unix seconds), `platform: 3`, `vName: 1.0.0`, `sk-language: en`, `Origin`/`Referer: https://game.skport.com/`, plus a UA (the Skport Android app or desktop Firefox) | Areha; canaria; skport-api-docs "Standard Headers" |
| Origin/Referer | must be present: without them the API answers `19001` "无法获取当前角色位置" ("cannot determine current role") | Areha #3 (2026-07-02); #5 is still open with the same code since 2026-08-01 |
| Signature V2 | `md5_hex(hmac_sha256_hex(salt, path + body + timestamp + headerJson))` | skport-api-docs "Request Signing"; Areha `generateSignV2` |
| Token expiry | `code 10000` per canaria, `10002` per nano-shino; the two disagree | canaria `main-discord.gs`; `nano-shino/EndfieldCheckin` `EndfieldAutoCheckIn.js` |
| Already signed | unconfirmed: nano-shino matches `1001`/`10001`/"already", and canaria #1 quotes "Please do not sign in again!" | nano-shino `handleResponse` |
| Reset | unverified for the SKPort calendar; the in-game reset is 04:00 server-local (Asia UTC+8, Americas UTC-5, Europe UTC+1) | endfieldhub.org/guides/reset-time (secondary) |

```python
def skport_sign(path: str, body: str, ts: str, salt: str) -> str:
	# Key order and compact separators must match JS JSON.stringify byte for byte.
	hdr = json.dumps({"platform": "3", "timestamp": ts, "dId": "", "vName": "1.0.0"}, separators=(",", ":"))
	mac = hmac.new(salt.encode(), (path + body + ts + hdr).encode(), hashlib.sha256).hexdigest()
	return hashlib.md5(mac.encode()).hexdigest()
```

Auth follows `AixLnyt/skport-api-docs` "Authentication Flow":

1. Email and password login (`as.gryphline.com/user/auth/v1/token_by_email_password`) needs a `captchaToken`, so it is human-only.
2. That login yields `ACCOUNT_TOKEN`, an HttpOnly cookie on `.skport.com`. It is also readable as JSON at `https://web-api.skport.com/cookie_store/account_token` while logged in (nano-shino README). It may arrive percent-encoded, so URL-decode it (Areha #2).
3. Each run, `POST as.gryphline.com/user/oauth2/v2/grant` with `{token, appCode: "6eb76d4e13aa36e6", type: 0}` returns `data.code`.
4. `POST zonai.skport.com/web/v1/user/auth/generate_cred_by_code` with `{kind: 1, code}` returns `data.cred` and usually `data.token`, which is the salt. When the token is missing, `GET /web/v1/auth/refresh` with a `cred` header returns it (canaria PR #4; nano-shino).

The browser-scraped `cred` and salt (`SK_OAUTH_CRED_KEY` and `SK_TOKEN_CACHE_KEY`) **expire daily** (canaria #2), so they are unusable unattended. `ACCOUNT_TOKEN` lasts "a few weeks or months, or until you log out" (Areha README FAQ). **Verdict:** `cred` and the salt refresh automatically from `ACCOUNT_TOKEN`; `ACCOUNT_TOKEN` itself needs a manual re-paste.

## Design

1. **A new app, `backend/checkins/`.** A check-in is a write with side effects, so it is not a `Strategy` and shares nothing with `Link` scraping. It holds the models, two clients (`hoyolab.py`, `skport.py`), `service.py` and the views.
2. **Typed outcomes, so impossible states stay impossible.** Each client exposes `run(creds) -> Outcome`, and `Outcome` is a closed union: `Claimed(reward, month_count)`, `AlreadyClaimed(month_count)`, `NeedsCredentials(code, msg)`, `Captcha`, `Transient(code, msg)` or `Broken(code, msg)`. Any unknown non-zero code or schema mismatch is `Broken`, keeping the raw code and a 500-char message. Upstream JSON is parsed with pydantic at the boundary.
3. **Idempotent flow.** The client reads status (`is_sign` / `hasToday`), POSTs only when it is false, then **re-reads status to confirm**. That guards against HoYoLAB's captcha "phantom success" (genshin.py #131). It also means Notif never depends on the disputed SKPort "already signed" codes.
4. **Models**

| Model | Fields |
|---|---|
| `CheckinAccount` | `user` FK (owner-scoped like `Strategy`: the 2026-07-03 audit decision makes Notif de jure multi-user, and registration is open), `platform`, `game` (TextChoices), `label`, `enabled`, `credentials` (Fernet token, empty means none), `credentials_updated_at`, `state` (`ok` / `needs_credentials` / `broken`), `next_run_at` (indexed), `attempts_today` (≤ 5), `last_error` (500) |
| `CheckinDay` | `account` FK, `day` (platform-local date), `outcome`, `attempts`, `reward` (200), `month_count` (nullable), `upstream_code` (nullable), `message` (500), `updated_at`; `unique(account, day)` |

5. **Credentials at rest.** A new `cryptography` dependency provides `MultiFernet` over `CHECKIN_FERNET_KEYS` (comma-separated, first key primary) in `notif/config.py`. Without a key the feature fails closed and accepts no credentials. The plaintext is a pydantic-validated JSON blob (`ltuid_v2`/`ltoken_v2`/`ltmid_v2`, or `account_token`). The API is **write-only** for credentials and never logs them; hoyolab-auto PR #136 had to stop dumping cookies into its logs. **What it protects:** the SQLite file, the backups under `/app/data/backups/` and any copy taken off-box, admin and serializer slips, and a DB copy pulled down for debugging. **What it does not protect:** a compromised VPS or backend container, because the key in `backend/.env` and the DB sit on the same host. That is acceptable: the threat is leaked backups, not root. Rotation means prepending a key, running `manage.py checkin_rotate_key`, then dropping the old key.
6. **Outbound HTTP.** `safe_fetch.request_capped` today takes only form `data`. It gains `headers=` and a raw `body: bytes` (for JSON), a small change to a security module that gets its own commit and tests. Each run uses one `guarded_session()` per account with `allow_redirects=False`, so credentials never follow a redirect. A hard-coded host whitelist of `sg-hk4e-api.hoyolab.com`, `sg-public-api.hoyolab.com`, `as.gryphline.com` and `zonai.skport.com` is asserted before every request.
7. **Scheduling.** `run_due_tasks` gains `_run_due_checkins()` before the scrapes, capped by `--max-checkins` (default 10) and the existing runtime cap and lock.
   1. **Normal run:** `next_run_at` = the next platform reset + 20 minutes + 0-40 minutes of jitter. HoYoLAB resets at 16:00 UTC. SKPort uses the account's server reset; until that is verified, server 3 runs at 10:00 UTC, which falls after both the 03:00 and 09:00 UTC candidates.
   2. **`Transient`:** retry at +15, +30, +60 and +120 minutes, at most 5 attempts per day; after that the day is `failed`.
   3. **`NeedsCredentials` / `Captcha`:** no retry today. For `NeedsCredentials`, the account sits in `state=needs_credentials` until a re-paste resets it.
   4. **Housekeeping:** every attempt writes a `SystemEvent` (source `checkins`, no secrets), and `CheckinDay` rows older than 400 days are pruned.
8. **Status endpoint.** `GET /api/checkins/` (owner-scoped) returns, per account: platform, game, label, state, the last `CheckinDay`, `next_run_at`, `month_count`, and a streak of consecutive claimed or already-claimed days. Credentials go through `PUT /api/checkins/{id}/credentials/`, write-only and returning 204, and `POST /api/checkins/{id}/run/` sets `next_run_at=now`. The OpenAPI file is regenerated.
9. **Failure notification.** `Notification` is one-to-one with `Update`, which requires a `Link`. The cheapest path gives each account a shim `Link` (`scrape_disabled=True`, `strategy=None`, the URL set to the sign-in page) and creates an `Update` plus `Notification` on it **on state transitions only**: entering `needs_credentials`/`captcha`/`failed`, never daily spam. The shim shows up in the Link list; see open question 4.
10. **Flutter.** A `screens/checkins.dart` with a `services/checkins.dart` built on the generated OpenAPI types. Each account gets one card: game, outcome chip, reward, "12/31 this month", next run in local time, and the error with a "paste new credentials" action for a write-only paste form.

## Failure modes

| Mode | Signal | Notif action |
|---|---|---|
| HoYoLAB captcha | `retcode 0` with `risk_code != 0`, `gt` and `challenge`; status re-read says unsigned | `Captcha`: notify, no retry today, try again tomorrow. Only a human can clear it, by clicking on the web; paid solvers are out of scope |
| Captcha frequency | daily throughout Jul-Aug 2023, every 3-4 days in Jun 2023, then gone by Sep 2023 (genshin.py #134, #131; hoyolab-auto-sign #22). No reports in hoyolab-auto (active to 2026-10) or genshin.py since 2024 | Rare today (*inference*, 70%), but HoYo has switched it on for weeks before |
| HoYoLAB expired cookie | `-100`, `10001` or `-1071` | `NeedsCredentials`; notify once |
| SKPort expired token | the grant step fails (`status != 0`), or `10000`/`10002` | `NeedsCredentials`; notify once |
| SKPort role or headers | `19001` | `Broken`; notify. Usually header drift, as in Areha #3 and #5 |
| Endpoint drift | HoYo `-500012` "活动已结束" (event ended) when the ZZZ endpoint moved in 2024-10 (hoyolab-auto-sign #52); ZZZ broke again in 2025-12, cause not stated (#63) | `Broken`; notify; a code fix follows |
| Rate limit | HoYo `-1004`/`-500004`/`-110`; HTTP 429 | `Transient`, bounded retry, as Croissant does in `AttendCheckInEventWorker.kt` |
| Network or 5xx | `RequestException`, `DeadlineExceededError` | `Transient` |
| Clock skew | SKPort signs a unix timestamp | The VPS needs NTP (`timedatectl`); verify once |
| Fingerprint | prior art runs from Google Apps Script, which is datacenter IPs, without trouble | The Hetzner IP is probably fine (*inference*, 75%); send the prior-art headers and jitter the run time |

## Is it simple?

**The calls are simple; the feature is not.** A HoYoLAB claim is one unsigned POST with a pasted cookie, about 30 lines. SKPort is a three-call OAuth chain plus a 4-line HMAC-then-MD5 signature, about 80 lines. Neither needs a headless browser, a DS salt or a login flow.

**The real work comes in two kinds.**

1. **Fitting Notif's invariants.** This means encrypted credentials with rotation, JSON POSTs through the SSRF guard, scheduler state with bounded retries, an idempotent per-day log, typed outcomes, a write-only API with an OpenAPI regen, and a notification path that the current `Update` → `Link` schema does not naturally offer.
2. **Ongoing upkeep.** Prior art broke on upstream changes in 2024-10 (HoYo ZZZ), 2025-12 (ZZZ again), 2026-02 (SKPort auth), 2026-07 (SKPort `19001`) and 2026-08 (`19001` again, still open). Expect a fix every two to four months per platform (*inference*, from five breaks in two years across both platforms), plus a re-paste whenever a token dies.

**Effort, in sessions of about 2-3 focused hours each, including tests and CI parity:**

| Part | Sessions |
|---|---|
| Backend: the `safe_fetch` extension, models, HoYoLAB client, scheduler hook, status endpoint, fixture tests | 2 |
| Backend: SKPort client (OAuth chain, signing, binding, fixtures) | 1-1.5 |
| Credentials: Fernet/MultiFernet, config, write-only API, rotate command, tests | 1 |
| Notifications: the shim `Link` (0.5), or a nullable `Update.link` schema change instead (1.5) | 0.5-1.5 |
| Frontend: status screen and paste form | 1-1.5 |
| **Total** | **5.5-7.5** |

That is about 1-1.5 sessions per platform in the first year for drift fixes (*inference*, from the cadence above).

## Phased plan

1. **M1: HoYoLAB Genshin, headless (2 sessions).** Extend `request_capped`, then add `CheckinAccount` and `CheckinDay` and the HoYoLAB client with recorded-JSON fixture tests. Fixtures cover every `Outcome` branch, including captcha with `retcode 0` and a status re-read that says unsigned. Then the `run_due_tasks` hook and `GET /api/checkins/`. Credentials come from `CHECKIN_HOYOLAB_COOKIE` (a `SecretStr`) in the env. No UI, no notifications. **Done when** the VPS shows 7 consecutive `claimed`/`already_claimed` days in `SystemEvent`.
2. **M2: credentials at rest and notifications (1.5-2.5 sessions).** Fernet, credentials moved into the DB, and the shim-`Link` notifications. Remove the env cookie.
3. **M3: SKPort Endfield (1-1.5 sessions).** Before coding, inspect one real browser request in DevTools to confirm the reset time, the "already signed" code and the `19001` headers.
4. **M4: Flutter screen and paste form (1-1.5 sessions).**
5. **M5, optional:** more HoYo games, about 0.25 session each, since they share the client family.

## Risks

| Risk | Mitigation |
|---|---|
| These tokens are account-level sessions: Notif holding them means a DB+env leak is near account takeover (Areha README: the token "represents your direct access to your account") | Fernet, write-only API, no logging; scope stays limited to check-ins |
| Signing bugs in the JSON separators, key order or the hex case of the `sign` header | A golden vector from an independent node `crypto` port of the prior-art JS, checked against the Python |
| Silent phantom success | Re-read status after every claim |
| Notification noise | Notify on transitions only |
| Upkeep outlives the interest (TODO marks this "low priority") | Phase gates: stop after M1 if it proves flaky |

## Open questions for Luka

1. Which HoYo games: Genshin only, or also HSR and ZZZ? ZZZ is the most drift-prone.
2. Your Endfield server: 2 (Asia) or 3 (Americas/Europe)? Your Genshin region does not change the endpoint.
3. Do you already have the cookies, and are you fine pasting `ltoken_v2`/`ltuid_v2`/`ltmid_v2` and `ACCOUNT_TOKEN` into Notif?
4. For failure notifications: is a shim `Link` per account acceptable for now, or should `Update` get a nullable `link` and a `source` first?
5. Should Fernet also cover the existing plaintext `Strategy.data` passwords (QQ, Kemono)? It is adjacent and not in this plan.
