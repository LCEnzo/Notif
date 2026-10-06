# Plan: Health Connect export

Status: **proposal, planning only** · Date: 2026-10-06 · APK distribution: see the separate F-Droid plan.

## Goal

Move Luka's Health Connect (HC) data off the phone into Notif, unattended, at a fidelity that serves
multi-year trend analysis, in a budget of about 10 MB per year (never gigabytes). Backfill the full
history, so the read-history permission is a requirement, not an option. Out of scope: real-time
sync, iOS, writing to HC, exercise GPS routes, and analysis tooling beyond an export format.

## Constraints and verified facts

"Src" means read in source code; "Docs" means official docs; "Inf" means my inference.

| # | Fact | Basis |
|---|---|---|
| 1 | Without the history permission, reads **silently omit** data older than 30 days before the app's *first* HC grant (only single `readRecord` errors). This applies to `readRecords`, `aggregate*` and `getChanges`. | Src: [HealthPermission.kt](https://github.com/androidx/androidx/blob/androidx-main/health/connect/connect-client/src/main/java/androidx/health/connect/client/permission/HealthPermission.kt) |
| 2 | History permission: `android.permission.health.READ_HEALTH_DATA_HISTORY` (`HealthPermission.PERMISSION_READ_HEALTH_DATA_HISTORY`), gated by `HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_HISTORY`. | Src: same file |
| 3 | The history and background features need **Android 14 (API 34) with SDK extension ≥ 13**, or the **HC APK versionCode ≥ 171302** on Android 13 and lower. | Src: [HealthConnectFeatures.kt](https://github.com/androidx/androidx/blob/androidx-main/health/connect/connect-client/src/main/java/androidx/health/connect/client/HealthConnectFeatures.kt) `FEATURE_TO_VERSION_INFO_MAP` |
| 4 | Uninstalling the app revokes every grant, history included. A re-grant re-anchors the 30-day window. | Docs: [aggregate-data](https://developer.android.com/health-and-fitness/guides/health-connect/develop/aggregate-data), "Permissions history for a deleted app" |
| 5 | Background reads need `android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND` (feature `FEATURE_READ_HEALTH_DATA_IN_BACKGROUND`). Without it, reads work only in the foreground. | Docs: [read-data](https://developer.android.com/health-and-fitness/guides/health-connect/develop/read-data) |
| 6 | Aggregation comes in three forms: `aggregate`, `aggregateGroupByDuration` (takes `Instant`), and `aggregateGroupByPeriod` (needs `LocalDateTime`; `Instant` throws). Empty buckets are omitted. | Docs: aggregate-data |
| 7 | **Only Activity and Sleep aggregates are deduplicated** by the user's app priority. Other types sum every app that wrote them. Summing raw steps from both a phone and a watch double-counts. | Docs: aggregate-data |
| 8 | Aggregate metrics exist for HR (`BPM_AVG/MIN/MAX`, `MEASUREMENTS_COUNT`), resting HR, weight, steps, distance and calories. None are listed for SpO2, HRV or respiratory rate. | Docs: aggregate-data. The "none" part is Inf from their absence in the list. |
| 9 | Raw reads default to `pageSize` 1000. The page token can come back as `""`, so check it with `isNullOrEmpty`. | Docs: read-data |
| 10 | Changes API: `getChangesToken(types)` then `getChanges(token)`. `DeletionChange` carries only the record id. **An unused token expires within 30 days**; the fallback is to re-read from the last cursor and dedupe by id. | Docs: [sync-data](https://developer.android.com/health-and-fitness/guides/health-connect/develop/sync-data) |
| 11 | Read quotas: foreground 2,000 calls per 15 min and 16,000 per 24 h; background 1,000 per 15 min and 8,000 per 24 h. Each call costs 1, whatever its record count. The docs publish no numbers, and these are server-tunable defaults. | Src: [RateLimiter.java](https://android.googlesource.com/platform/packages/modules/HealthFitness/+/refs/heads/main/framework/java/android/health/connect/ratelimiter/RateLimiter.java), [rate-limiting](https://developer.android.com/health-and-fitness/health-connect/rate-limiting) |
| 12 | `connect-client` 1.1.0 is the latest stable (2025-10-08); 1.2.0-alpha06 is the latest alpha. The library needs minSdk 26 (androidx-main `build.gradle` and [get-started](https://developer.android.com/health-and-fitness/guides/health-connect/develop/get-started)); the 1.2.0-alpha05 notes say 24. The conflict is moot because the HC app itself needs API 28. | Src and Docs: [releases](https://developer.android.com/jetpack/androidx/releases/health-connect) |
| 13 | The manifest needs a rationale activity (`ACTION_SHOW_PERMISSIONS_RATIONALE`) plus a `VIEW_PERMISSION_USAGE` activity-alias on Android 14+. | Docs: get-started |
| 14 | On-device auto-delete is user-set: Never, 3 months, or 18 months. | Src: AOSP `AutoDeleteRange.kt` |
| 15 | HC's built-in export (Android 14+) writes a daily, weekly or monthly zip to a cloud provider. The zip holds `health_connect_export.db`, a copy of HC's **internal** SQLite schema. The class doc says "encrypted copy", but the export package contains no encryption code. **Unverified.** | Docs: [backup help](https://support.google.com/android/answer/15323271); Src: AOSP `ExportManager.java` |
| 16 | Repo: the Android target exists. minSdk and targetSdk come from Flutter defaults (24 and 36 on the local Flutter 3.44.8). The `applicationId` is still `com.example.notif`. | Src: `frontend/android/app/build.gradle` |
| 17 | Repo: device sessions die 14 days after last use or **90 days after creation**, so an unattended phone loses its session at least every 90 days. | Src: `backend/notif/config.py` |
| 18 | Repo: architecture tests allow only `session_store` to touch secure storage, and only `api_client` to touch dio or build `Authorization`. | Src: `frontend/test/architecture_test.dart` |
| 19 | Repo: neither Caddy nor the Django settings cap request body size. | Src: `Caddyfile`, `settings_base.py` |

## Options

**A. Phone-side access to HC**

| | `health` 13.3.2 ([pub.dev](https://pub.dev/packages/health), carp.dk) | In-app Kotlin bridge (about 5 MethodChannel calls) |
|---|---|---|
| Maintenance | Verified publisher. 14 releases since 2025-04, but the last gap was 2026-02-06 to 2026-08-14. | Ours to maintain |
| HR aggregates | Maps `HEART_RATE` to `MEASUREMENTS_COUNT` only. No avg/min/max, no resting-HR aggregate (`HealthConstants.kt`). | Any metric |
| Local-day buckets | Duration slicing only, no `aggregateGroupByPeriod` | Period slicing over `LocalDateTime` |
| Errors | `getChanges` and `getChangesToken` return `null` on any exception | Typed, mapped to `AppFailure` |
| History and background permissions | Supported | Supported |
| Dependency | Pins `connect-client:1.2.0-alpha02` and brings an iOS surface | Pins 1.1.0 stable |
| Tests | None in the repo | `FakeHealthConnectClient` (`connect-testing` 1.0.0-alpha04) |
| Cost | No Kotlin | About 300–500 lines of Kotlin plus tests (Inf) |

**B. Scheduling**

| | `workmanager` 0.10.10 (Dart callback in a background isolate) | Native `CoroutineWorker` doing the upload | Foreground only, on app resume |
|---|---|---|---|
| Architecture tests (fact 18) | Intact: upload goes through `api_client` | Broken: Kotlin needs the token and builds its own HTTP | Intact |
| Unattended | Yes, with the background permission | Yes | No |
| Main risk | The bridge must register in the background engine | Duplicated auth stack | Luka has to open the app |

**C. Transport**

| | Authenticated endpoint with idempotent batched upserts | File exported on the phone (SAF / Downloads) | HC built-in export zip |
|---|---|---|---|
| Unattended | Yes | No, Luka moves files | Yes, but it lands in a cloud drive and the backend does not fetch |
| Idempotency | Upsert keys | None; one file per run | Whole snapshot every time |
| Schema | Ours, stable | Ours | HC internal; can change with any mainline update |
| Fits "through Notif" | Yes | Partly | No |

## Recommendation

1. **Phone:** build a Kotlin bridge as a local Flutter plugin package (`frontend/packages/hc_bridge/`) on `connect-client` 1.1.0. Being a real plugin means the generated registrant also loads it into WorkManager's background engine. It exposes `status`, `requestPermissions`, `aggregateBuckets`, `readRecords` and `changes`. Dart owns orchestration and uploads through `api_client`, so fact 18 holds.
2. **Fidelity:** dense types (steps, distance, active and total kcal, HR) get **hourly HC aggregates** (UTC-hour buckets, deduplicated by HC where fact 7 applies), kept forever. Sparse types (sleep with stages, exercise sessions, resting HR, HRV, weight, body fat, SpO2) get **raw records**, kept forever. No raw dense series goes to the server; HC on the phone and its built-in export cover deep dives.
3. **Sync:** a WorkManager job every 24 h with a network-connected constraint, plus a sync on app resume. Each run re-aggregates the trailing 7 days to catch late wearable syncs. Sparse types use change tokens; when a token expires, re-read from the stored cursor and upsert by HC id. Days offline only widen the next run's window; each request covers at most 7 days and each run at most 90 days.
4. **Backend:** a new Django app, `health`, separate from `monitoring` (scraping) because it is a different bounded context. Endpoint: `POST /api/health/ingest`, bearer session.
   1. Aggregates upsert on `(metric, bucket_start)`, records on the HC record id plus `lastModifiedTime` (newer wins), deletions by id.
   2. The view enforces its own caps of 2,000 items and 1 MB per request (fact 19).
   3. No outbound HTTP.
5. **Session death (fact 17):** a 401 carrying `WWW-Authenticate: Session` posts a local "sign in to resume health sync" notification. A write-only ingest credential is worth building only if re-logging in every quarter gets annoying.
6. **Analysis:** `manage.py export_health` writes long-format CSV (UTC epoch plus offset columns) with the stdlib only. DuckDB and pandas read it directly. Parquet is not worth a pyarrow dependency at about 5 MB a year.

The hourly read has this shape (one call, several metrics, 7 days):

```kotlin
client.aggregateGroupByDuration(AggregateGroupByDurationRequest(
    metrics = setOf(StepsRecord.COUNT_TOTAL, HeartRateRecord.BPM_AVG, HeartRateRecord.BPM_MIN,
        HeartRateRecord.BPM_MAX, HeartRateRecord.MEASUREMENTS_COUNT),
    timeRangeFilter = TimeRangeFilter.between(weekStart, weekEnd), // Instant, UTC
    timeRangeSlicer = Duration.ofHours(1),
)) // List of groups: startTime, endTime, zoneOffset, result[metric]
```

**History permission flow (mandatory):**

1. On "Connect Health Connect", call `getSdkStatus`. If it reports that a provider update is needed, deep-link to the HC update.
2. Check `getFeatureStatus(FEATURE_READ_HEALTH_DATA_HISTORY)` and `getFeatureStatus(FEATURE_READ_HEALTH_DATA_IN_BACKGROUND)`.
3. Launch `PermissionController.createRequestPermissionResultContract()` with one HC sheet requesting the type reads, history and background, as in the [androidx sample](https://github.com/androidx/androidx/blob/androidx-main/health/connect/connect-client/samples/src/main/java/androidx/health/connect/client/samples/PermissionSamples.kt).
4. Persist `history_granted`, `background_granted` and `first_grant_at`. With history granted, run a one-shot, foreground, resumable backfill in monthly chunks that shows progress.
5. If history is **denied or unavailable**, sync still runs. The backfill floor is `first_grant_at − 30 d`, and every batch carries `coverage_start` so the backend can tell "nothing readable" from "zero" (fact 1: HC returns empty, not an error). Settings shows "Past data off: nothing before <date> exported" with a button that requests the history permission alone. A later grant triggers the backfill. If the feature is unavailable, the UI adds an "update Health Connect" hint.
6. If background is denied, sync runs only on app resume, and a banner says so.

## Storage estimate

Row sizes were measured in SQLite after `VACUUM`, with a unique index included:

| Layout | Bytes per row |
|---|---|
| Sample row with integer epoch | 33.6 |
| Aggregate row as Django defaults would create it (text metric, `DateTimeField` stored as text) | 139 |
| Aggregate row with integer keys | 53.6 |
| Raw record row keyed by HC UUID (text times, two indexes) | 257 |

Parquet measured 0.8 B/sample on a synthetic HR random walk; real data is noisier, so I assume 1–3 B. Sample rates depend on the device and are assumptions.

| Type | Assumed rate | Raw per year | Hourly per year (139 B) | Daily per year | Keep |
|---|---|---|---|---|---|
| HR | 1 sample / 5 s | 6.31 M × 33.6 B = **212 MB** (1 s: 1.06 GB; 60 s: 17.7 MB) | 8,760 × 139 B = 1.22 MB | 365 × 139 B = 51 KB | hourly |
| Steps | 500 records / day (guess) | 182.5 k × 257 B = 47 MB | 1.22 MB | 51 KB | hourly |
| Distance, active kcal, total kcal | like steps | about 47 MB each | 1.22 MB each | 51 KB each | hourly |
| Sleep | 1 session + 40 stages / night | 365 × 257 B + 14.6 k × 40 B = 0.68 MB | (session-shaped) | 51 KB | raw |
| Resting HR, exercise session, weight, body fat | ≤ 1 / day each | ≤ 365 × 257 B = 94 KB each | — | — | raw |
| HRV, SpO2 | 1 / night | 94 KB each; if a watch writes every minute overnight, 480 × 365 × 257 B = 45 MB | no HC aggregate | — | raw; switch to hourly on the phone if dense |

**Recommended total:** 5 hourly metrics × 1.22 MB = 6.1 MB, plus sparse raw records (0.68 + 6 × 0.094 ≈ 1.3 MB), comes to **about 7.4 MB a year** (about 75 MB per decade) with Django-default columns. Integer bucket keys bring that to 5 × 8,760 × 53.6 B + 1.3 MB ≈ 3.7 MB; that is a reserve lever, not a starting point.

Optional upgrades: HR at 15-minute buckets costs +3.7 MB a year; a raw HR Parquet archive at 5 s costs 6–19 MB a year, which breaks the budget at the high end.

**What each step down loses:**

1. **Raw to hourly:** sub-hour dynamics (HR recovery curves; peaks shorter than an hour collapse into max), which app wrote what, and the ability to re-dedupe later. HC aggregates bake in whatever app priority was set when they were computed.
2. **Hourly to daily:** circadian shape (the nocturnal HR dip, the time of day activity happens) and hour × weekday patterns. Daily values can be derived from hourly ones (sums exactly; HR mean weighted by `n`), so hourly loses nothing to daily, at 24× the rows.

## Phased plan

1. **Phase 0, decisions with no code:**
   1. Settle the final `applicationId` with the F-Droid plan. HC grants belong to the package, and the 30-day anchor resets on reinstall.
   2. Set `minSdk 26` explicitly.
   3. Run a 1-hour on-device spike: feature status for history and background, an HC grant to a sideloaded build (Inf: should work), and the bridge running inside the WorkManager isolate.
2. **Phase 1, milestone M1:** hourly steps, resting HR (raw) and sleep sessions with stages (raw).
   1. Full permission flow, including history and background.
   2. Backfill, then the daily WorkManager sync over the trailing 7 days.
   3. Backend `health` app, the ingest endpoint and the `export_health` CSV command.
   4. Tests: the bridge against `FakeHealthConnectClient`, and a Hypothesis property on the backend: any permutation or duplication of the same batches converges to the same rows.
3. **Phase 2, breadth:** hourly HR, distance and kcal; raw exercise sessions, HRV, weight, body fat and SpO2; change tokens with deletion handling for the sparse types.
4. **Phase 3, robustness:** a staleness check in `run_due_tasks` (no batch for 72 h emits a `SystemEvent`), the 401 notification, and per-type daily row counts to catch dense SpO2 or HRV.
5. **Phase 4, optional:** 15-minute HR or a raw HR archive, decided on real Phase 1–2 volumes.

Interim until M1: Takeout only covers data that reached Google's cloud (Fit and Fitbit), not HC-only sources (Inf, high confidence). HC's built-in export is the better stopgap for a full snapshot.

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Reads outside the window return empty, so gaps pass for zeros | High if history is denied | `coverage_start` stored per batch; the export flags uncovered days |
| The bridge does not register in the background isolate | Medium | Ship it as a local plugin package; the Phase 0 spike settles it |
| The session hits 90 days and sync stops silently | Certain without handling | 401 notification plus the Phase 3 staleness check |
| Wearables sync later than 7 days | Low to medium | The trailing window is a setting; change tokens for raw types |
| SpO2 or HRV turn out dense and break the budget | Device-dependent | Per-type counts; summarize hourly on the phone |
| Auto-delete set to 3 or 18 months erases history before the backfill | Unknown | Check the setting now (Q3) |
| A priority change alters recomputed aggregates | Low | Only 7 days are ever recomputed; store `computed_at` |
| Rate limits | Low | Daily sync is about 10 calls; backfill runs in the foreground (2,000 per 15 min), chunked |

## Open questions for Luka

1. Which phone (model, Android version), and which apps or wearables write to HC (Pixel or Fitbit, Samsung, Garmin, ...)? That sets HR density and whether SpO2 and HRV are dense.
2. Which metrics matter beyond the default set: steps, HR, resting HR, HRV, sleep, exercise, weight, body fat and SpO2?
3. Is HC auto-delete set to **Never**? If not, history is already being lost; run HC's built-in export now.
4. Is re-logging in every quarter acceptable, or should Notif get a write-only ingest credential?
5. Is hourly HR enough, or should HR use 15-minute buckets (+3.7 MB a year)?
6. Do you open Notif on the phone most days? If so, foreground sync alone is viable and background becomes a nicety.
7. Can you enable HC's built-in export once and check whether the zip is plain SQLite? That settles fact 15 and gives a backfill cross-check.
