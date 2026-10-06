# Plan: game daily check-ins (HoYoLAB, SKPort)

Status: **proposal, not implemented** · Date: 2026-10-06 · Source: the "Game Daily Check-ins" section of the local, gitignored `TODO.md`

## Goal

Notif claims the daily web check-in reward for Genshin Impact (HoYoLAB) and Arknights: Endfield (SKPort) on a schedule. It records one result per account per day, raises a Notification when a run needs a human, and shows a small status screen: last run, outcome, reward, monthly count, next run. Code redemption and "make-up" sign-ins are out of scope.

Luka decided on 2026-10-06: the scope is Genshin and Endfield, with HSR and ZZZ later (their act_ids are in `genshin/client/routes.py` `REWARD_URL`). Both accounts are on European servers; Genshin EU uses the shared overseas endpoint, and Endfield is server `3`. All HTTP goes through `safe_fetch` (Design 6), and credentials never travel through chat or a commit.

## Verified facts per platform

Facts cite prior-art code or issue threads. *Inference* marks my own reasoning, and percentages are my confidence.

### HoYoLAB (Genshin, overseas)

| Item | Fact | Source |
|---|---|---|
| Endpoints | `https://sg-hk4e-api.hoyolab.com/event/sol/` with `sign` (POST), `info` and `home` (GET), plus the query `act_id=e202102251931481&lang=en-us` | `seriaati/genshin.py` (formerly thesadru) `genshin/client/routes.py`; `torikushiii/hoyolab-auto` `hoyolab-modules/genshin/index.js` |
| Body | none, since `act_id` goes in the query. Croissant also sends JSON `{"act_id": ...}`; both work | `genshin/client/components/daily.py`; Croissant `GenshinImpactCheckInService.kt` |
| Headers | `Cookie`, `Referer: https://act.hoyolab.com/`, a desktop Chrome UA and `x-rpc-signgame: hk4e`; optionally `x-rpc-app_version: 1.5.0` and `x-rpc-client_type: 5`. **No DS signature overseas** | `daily.py` `request_daily_reward`; `hoyolab-auto` `gots/hoyolab/index.js` |
| Status | `{retcode, message, data}`. `info` returns `data.is_sign`, `data.total_sign_day` and `data.today`. `home` returns `data.awards[] {name, cnt, icon}` | `genshin/models/genshin/daily.py`; `hoyolab-auto` `check-in.js` |
| Codes | `0` ok; `-5003` already claimed; `-100`/`10001`/`-1071` invalid cookie; `-10002` no game account; `-1004`/`-500004`/`-110` too frequent | `genshin/errors.py` `_errors`; Croissant `HoYoLABRetCode.kt` |
| Captcha | `retcode 0`, yet `data` (or `data.gt_result`) has `risk_code != 0` with a `gt` and a `challenge`. The claim **did not happen** | `genshin/errors.py` `check_for_geetest`; genshin.py #131 ("phantom reward collection") |
| Day boundary | 00:00 UTC+8, i.e. 16:00 UTC, for every overseas server | `daily.py` computes `missed_rewards` in `CN_TIMEZONE` (*inference*, 85%) |

The auth cookies are `ltuid_v2` and `ltoken_v2`, plus `ltmid_v2`, which some endpoints need (genshin.py #151). They are HttpOnly, so JavaScript cannot read them (canaria3406/hoyolab-auto-sign #26). Their lifetime is undocumented: a password change kills them (#26), one user reports "expired after few months" (#62), and the hoyolab-auto maintainer reports about a year (hoyolab-auto #143, 2026-09). Automated refresh needs an `stoken` (`genshin/client/manager/cookie.py`), which browsers no longer expose; it comes only from an app login with a geetest (hoyolab-auto PR #136). **Expiry means a manual re-paste.**

### SKPort (Endfield, server 3)

| Item | Fact | Source |
|---|---|---|
| Status | `GET https://zonai.skport.com/web/v1/game/endfield/attendance` returns `data.hasToday` | `Areha11Fz/ArknightsEndfieldAutoCheckIn` `EndfieldAutoCheckIn.js`; `AixLnyt/skport-api-docs` `README_EN.md` |
| Claim | `POST` to the same URL with **no body**, signed over body `""`. Success is `code 0` with `data.awardIds[]` and `data.resourceInfoMap{id: {name, count, icon}}` | Areha; `canaria3406/skport-auto-sign` `src/main-discord.gs` |
| Role | header `sk-game-role: 3_{roleId}_{serverId}`. Server `3` covers Americas and Europe. Auto-detect via `GET zonai.skport.com/api/v1/game/player/binding` | canaria `README.md`; Areha `fetchSkGameRole` |
| Headers | `cred`, `sign`, `timestamp` (unix seconds), `platform: 3`, `vName: 1.0.0`, `sk-language: en`, `Origin`/`Referer: https://game.skport.com/`, plus a UA | Areha; canaria; skport-api-docs "Standard Headers" |
| `19001` | "无法获取当前角色位置" ("cannot determine current role") when Origin/Referer are missing. It recurred on 2026-08-01 and is still open | Areha #3 (fixed 2026-07-02), Areha #5 |
| Token expired | `code 10000` per canaria, `10002` per nano-shino; the two disagree | canaria `main-discord.gs`; `nano-shino/EndfieldCheckin` |
| Already signed | unconfirmed: `1001`/`10001`, or the message "Please do not sign in again!" | nano-shino `handleResponse`; canaria #1 |
| Reset | in-game reset is 04:00 UTC+1, i.e. 03:00 UTC. **The check-in calendar reset is unverified**, and server 3 is shared with the Americas (04:00 UTC-5 = 09:00 UTC) | endfieldhub.org/guides/reset-time (secondary) |

```python
def skport_sign(path: str, body: str, ts: str, salt: str) -> str:
	# Key order and compact separators must match JS JSON.stringify byte for byte.
	hdr = json.dumps({"platform": "3", "timestamp": ts, "dId": "", "vName": "1.0.0"}, separators=(",", ":"))
	mac = hmac.new(salt.encode(), (path + body + ts + hdr).encode(), hashlib.sha256).hexdigest()
	return hashlib.md5(mac.encode()).hexdigest()
```

Auth, per skport-api-docs "Authentication Flow", Areha and canaria PR #4:

1. An email/password login needs a `captchaToken`. It is human-only and yields `ACCOUNT_TOKEN`, which lasts "a few weeks or months, or until you log out" (Areha README).
2. Each run, Notif exchanges that token. `POST as.gryphline.com/user/oauth2/v2/grant` with `{token, appCode: "6eb76d4e13aa36e6", type: 0}` returns `data.code`. `POST zonai.skport.com/web/v1/user/auth/generate_cred_by_code` with `{kind: 1, code}` returns `data.cred` and `data.token`, the signing salt. When the salt is missing, `GET /web/v1/auth/refresh` with the `cred` header returns it.
3. The browser's own `cred` and salt expire daily, so they cannot run unattended (canaria #2). **`ACCOUNT_TOKEN` expiry means a manual re-paste.**

### Getting the credentials

These steps are for Luka, at his own machine. **Never paste a credential into a chat, an issue or a commit.** In M1 he pastes it straight into `backend/.env` on the VPS himself. From M2 on, it goes through the write-only API or form.

1. **Open the cookie store.** Log in at `https://www.hoyolab.com` in a desktop browser, press F12, then go to Application (Chrome) or Storage (Firefox) → Cookies → `https://www.hoyolab.com`. Type `v2` in the filter box.
2. **Copy the values.** Copy the full Value of `ltuid_v2`, `ltoken_v2` and `ltmid_v2`. Select the whole cell: values can contain `-`, where a double-click selection stops short (genshin.py #151).
3. **Store them.** M1: `CHECKIN_HOYOLAB_COOKIE=ltuid_v2=...; ltoken_v2=...; ltmid_v2=...`, then restart the backend container. For Endfield: log in at `game.skport.com`, then copy the `ACCOUNT_TOKEN` cookie on `.skport.com`, or the JSON at `https://web-api.skport.com/cookie_store/account_token`; URL-decode it (Areha #2). Don't log out of either site afterwards.

## Design

1. **A new app, `backend/checkins/`.** It holds the models, `hoyolab.py`, `skport.py`, `service.py` and the views. It is not a `Strategy`: a check-in is a write with side effects, not a fetch-and-diff.
2. **Typed outcomes.** Each client exposes `run(creds) -> Outcome`, a closed union: `Claimed(reward, month_count)`, `AlreadyClaimed(month_count)`, `NeedsCredentials`, `Captcha`, `Transient` or `Broken`. The last four carry the upstream code and a 500-character message. Unknown codes and schema mismatches are `Broken`. Upstream JSON is parsed with pydantic at the boundary.
3. **Idempotent flow.** The client reads status (`is_sign` / `hasToday`) and POSTs only if unsigned. It then **re-reads status to confirm**, which catches captcha phantom successes and avoids the disputed SKPort codes.
4. **Models**

| Model | Fields |
|---|---|
| `CheckinAccount` | `user` FK, owner-scoped like `Strategy` (the 2026-07-03 audit decision makes Notif de jure multi-user); `platform`, `game`, `label`, `enabled`, `credentials` (a Fernet token), `credentials_updated_at`, `state` (`ok` / `needs_credentials` / `broken`), `next_run_at` (indexed), `attempts_today` (at most 5), `last_error` (500) |
| `CheckinDay` | `account` FK, `day` (platform-local date), `outcome`, `attempts`, `reward`, `month_count`, `upstream_code`, `message` (500), `updated_at`; `unique(account, day)` |

5. **Credentials at rest.** The new `cryptography` dependency provides `MultiFernet`, keyed by `CHECKIN_FERNET_KEYS` in `notif/config.py` (comma-separated; the first key is primary). Without a key the feature fails closed. The plaintext is a pydantic-validated JSON blob; the API is write-only for it, and nothing logs it (hoyolab-auto PR #136 had to stop dumping cookies into its logs). **It protects** the SQLite file, the backups under `/app/data/backups/`, any copy taken off-box, and admin or serializer slips. **It does not protect** against a compromised VPS, because the key in `backend/.env` sits on the same host; the threat is leaked backups, not root. Rotation: prepend a new key, run `manage.py checkin_rotate_key`, then drop the old key.
6. **Outbound HTTP: reuse `safe_fetch`, which is cheap.** The URLs are hard-coded, but a redirect, or a DNS answer pointing at a private address, could still carry the credentials to an internal host. `guarded_session()` blocks both by pinning connections to validated public addresses, and it already brings timeouts, a wall-clock deadline and body caps. The only change is a small `request_capped` extension, `headers=` plus a raw `body: bytes` for JSON, in its own commit with tests. Each account run uses one session, `allow_redirects=False`, and asserts a host whitelist: `sg-hk4e-api.hoyolab.com`, `as.gryphline.com`, `zonai.skport.com`.
7. **Scheduling.** `run_due_tasks` gains `_run_due_checkins()` before the scrapes, under the existing lock and runtime cap, plus `--max-checkins 10`. `next_run_at` is the reset + 20 minutes + 0–40 minutes of jitter. HoYoLAB uses 16:00 UTC. SKPort runs at 10:00 UTC until M3 verifies the calendar reset: 10:00 UTC falls after both candidate resets (03:00 and 09:00 UTC) and inside the same European day. `Transient` retries at +15, +30, +60 and +120 minutes, at most 5 attempts a day; `NeedsCredentials` and `Captcha` do not retry today. Each attempt writes a `SystemEvent` with no secrets, and `CheckinDay` rows older than 400 days are pruned.
8. **API.** `GET /api/checkins/` returns, per account: state, the last `CheckinDay`, `next_run_at`, `month_count`, and the streak. `PUT /api/checkins/{id}/credentials/` is write-only and returns 204. `POST /api/checkins/{id}/run/` makes the account due now. The OpenAPI file is regenerated.
9. **Notification home.** `Notification` hangs off `Update`, and `Update` requires a `Link`. Notifications fire only on state transitions (`needs_credentials`, `captcha`, `failed`), never daily. **Leaning: (b).**

| Option | Cost | Trade-off |
|---|---|---|
| (a) Shim `Link` per account (`scrape_disabled`, no strategy) | 0.5 session, no schema change | A fake source shows in the Link list with a dead scrape button; the model lies about what it is |
| (b) Nullable `Update.link` plus a nullable `Update.checkin_account` | 1.5 sessions: migration, serializers, OpenAPI, FE null-handling | An honest model, with a check constraint that exactly one of the two is set; it also gives later non-scrape sources a home |

10. **Flutter.** `screens/checkins.dart` and `services/checkins.dart`, built on the generated OpenAPI types. Each account is one card: game, outcome chip, reward, "12/31 this month", next run in local time, and a "paste new credentials" action.

## Failure modes

| Mode | Signal | Notif action |
|---|---|---|
| HoYoLAB captcha | `retcode 0` with `risk_code != 0`; the re-read says unsigned. Seen daily in Jul–Aug 2023, gone by Sep 2023 (genshin.py #134, #131). No reports since 2024 (hoyolab-auto is active to 2026-10) | `Captcha`: notify, retry tomorrow. Only a human can clear it, on the web. Rare today (*inference*, 70%) |
| Expired credentials | HoYo `-100`/`10001`/`-1071`; SKPort grant `status != 0`, or `10000`/`10002` | `NeedsCredentials`: notify once, wait for a re-paste |
| Upstream drift | SKPort `19001` (2026-07 and 2026-08); HoYo `-500012` when the ZZZ endpoint moved (hoyolab-auto-sign #52) | `Broken`: notify; a code fix follows |
| Rate limit, network, 5xx | HoYo `-1004`/`-500004`/`-110`, HTTP 429, `RequestException`, `DeadlineExceededError` | `Transient`, bounded retry, as in Croissant's `AttendCheckInEventWorker.kt` |
| Clock skew, fingerprint | SKPort signs a unix timestamp. Prior art runs from Google Apps Script, i.e. datacenter IPs | Verify NTP once (`timedatectl`). Send the prior-art headers. A Hetzner IP is probably fine (*inference*, 75%) |

## Is it simple?

**The calls are simple; the feature is moderately sized.** A HoYoLAB claim is one unsigned POST with a pasted cookie, about 30 lines. SKPort is three calls plus a 4-line signature, about 80 lines. Neither needs a headless browser or a login flow. The SSRF guard is a cheap reuse, not a cost. **The real work is two things:** encrypted credential storage (Fernet with rotation, a write-only API, no-logging discipline), and a notification home, which today's `Update` → `Link` schema lacks (Design 9).

Upkeep comes on top. Prior art broke on upstream changes in 2024-10, 2025-12, 2026-02, 2026-07 and 2026-08. Expect a fix every 2–4 months per platform, plus a re-paste whenever a token dies (*inference*).

| Part, in sessions of about 2–3 focused hours each | Sessions |
|---|---|
| Backend core: `request_capped` extension, models, HoYoLAB client, scheduler hook, status API, fixture tests | 2 |
| SKPort client: OAuth exchange, signing, role binding, fixtures | 1–1.5 |
| Credentials: Fernet, config, write-only API, rotation command, tests | 1 |
| Notification home: (a) 0.5 or (b) 1.5 | 0.5–1.5 |
| Frontend: status screen and paste form | 1–1.5 |
| **Total** (with (b): 6.5–7.5) | **5.5–7.5** |

## Phased plan

1. **M1: HoYoLAB Genshin, headless (2 sessions).** Extend `request_capped`, add the models and the HoYoLAB client with recorded-JSON fixtures for every `Outcome` branch, including captcha with `retcode 0`. Add the `run_due_tasks` hook and `GET /api/checkins/`. Luka pastes the cookie into the VPS env himself. No UI, no notifications. **Done when** the VPS shows 7 consecutive green days.
2. **M2: credentials at rest and the notification home (1.5–2.5 sessions).** Move the credentials into the DB, then remove the env cookie.
3. **M3: SKPort Endfield (1–1.5 sessions).** First, inspect one real browser request to confirm the calendar reset, the already-signed code and the `19001` headers.
4. **M4: Flutter screen and paste form (1–1.5 sessions).**
5. **Later: HSR and ZZZ**, about 0.25 session each, on the same client family.

## Risks

| Risk | Mitigation |
|---|---|
| These are account-level session tokens, so a DB-plus-env leak is close to an account takeover (Areha README) | Fernet, a write-only API, no logging, and credentials never sent through chat |
| A subtle signing bug: JSON separators, key order, or the hex case of `sign` | A golden vector from an independent node `crypto` port of the prior-art JS |
| Upkeep outlives the interest (TODO marks this "low priority") | Phase gates: stop after M1 if it is flaky |

## Open questions for Luka

1. Notification home: (a) a shim `Link`, or (b) a nullable `Update.link`? The plan leans towards (b).
2. Should Fernet also cover the existing plaintext `Strategy.data` passwords (QQ, Kemono)? That would be a separate change.
