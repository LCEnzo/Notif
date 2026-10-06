# Plan: Health Connect export

Status: **proposal, planning only** · Date: 2026-10-06 (revised for the larger budget and export profiles) · APK distribution: see the separate F-Droid plan.

## Goal

Move Luka's Health Connect (HC) data off the phone into Notif, unattended. That includes a one-time
backfill of everything HC holds (he expects 2–3 years). The data is kept at raw fidelity wherever the
budget allows, and comes back out through several export profiles. Budget: a few hundred MB per year
plus the backfill. Ceiling: never gigabytes. The read-history permission is a requirement. Out of
scope: real-time sync, iOS, writing to HC, exercise GPS routes, and analysis tooling.

## Constraints and verified facts

"Src" means read in source code; "Docs" means official docs; "Inf" means my inference.

| # | Fact | Basis |
|---|---|---|
| 1 | Without the history permission, reads **silently omit** records that start before *first HC grant − 30 days* (`Period.ofDays(30)`); only a single `readRecord` errors. This applies to `readRecords`, `aggregate*` and `getChanges`. | Src: [HealthPermission.kt](https://github.com/androidx/androidx/blob/androidx-main/health/connect/connect-client/src/main/java/androidx/health/connect/client/permission/HealthPermission.kt), AOSP `HealthConnectPermissionHelper.java` |
| 2 | The cutoff compares against the **record's own start time**, not when it was inserted. Records the calling app wrote itself are exempt. | Src: AOSP `RecordHelper.getFilterByStartAccessDateWhereClauses` |
| 3 | History permission: `android.permission.health.READ_HEALTH_DATA_HISTORY` (`HealthPermission.PERMISSION_READ_HEALTH_DATA_HISTORY`), gated by `HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_HISTORY`. | Src: HealthPermission.kt |
| 4 | The history and background features need **Android 14 (API 34) with SDK extension ≥ 13**, or the **HC APK versionCode ≥ 171302** on Android 13 and lower. | Src: [HealthConnectFeatures.kt](https://github.com/androidx/androidx/blob/androidx-main/health/connect/connect-client/src/main/java/androidx/health/connect/client/HealthConnectFeatures.kt) |
| 5 | Uninstalling the app revokes every grant, history included. A re-grant re-anchors the 30-day window. | Docs: [aggregate-data](https://developer.android.com/health-and-fitness/guides/health-connect/develop/aggregate-data), "Permissions history for a deleted app" |
| 6 | HC deletes no records on its own. Auto-delete is off (`0`) unless the user picks 3 or 18 months. | Src: AOSP `PreferencesManager`, `DailyCleanupJob`, `AutoDeleteRange.kt` |
| 7 | Background reads need `android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND` (feature `FEATURE_READ_HEALTH_DATA_IN_BACKGROUND`). | Docs: [read-data](https://developer.android.com/health-and-fitness/guides/health-connect/develop/read-data) |
| 8 | Aggregation comes in three forms: `aggregate`, `aggregateGroupByDuration` (takes `Instant`) and `aggregateGroupByPeriod` (needs `LocalDateTime`). Empty buckets are omitted. **Only Activity and Sleep are deduplicated** by the user's app priority; other types sum every app. | Docs: aggregate-data |
| 9 | Changes API: `getChangesToken(types)` then `getChanges(token)`. `DeletionChange` carries only the record id. An unused token expires within 30 days. Raw reads default to `pageSize` 1000, and an empty-string page token means done. | Docs: [sync-data](https://developer.android.com/health-and-fitness/guides/health-connect/develop/sync-data), read-data |
| 10 | Read quotas: foreground 2,000 calls per 15 min and 16,000 per 24 h; background 1,000 per 15 min and 8,000 per 24 h. Each call costs 1, whatever its record count. These are server-tunable defaults; the docs publish no numbers. | Src: [RateLimiter.java](https://android.googlesource.com/platform/packages/modules/HealthFitness/+/refs/heads/main/framework/java/android/health/connect/ratelimiter/RateLimiter.java) |
| 11 | `connect-client` 1.1.0 is the latest stable. The library needs minSdk 26, and the HC app needs API 28. The manifest needs a rationale activity plus a `VIEW_PERMISSION_USAGE` alias on Android 14+. | Docs: [get-started](https://developer.android.com/health-and-fitness/guides/health-connect/develop/get-started), [releases](https://developer.android.com/jetpack/androidx/releases/health-connect) |
| 12 | HC's built-in export (Android 14+) writes a zip of HC's **internal** SQLite schema (`health_connect_export.db`) on a schedule. It is unverified whether the zip is encrypted. | Docs: [backup help](https://support.google.com/android/answer/15323271); Src: AOSP `ExportManager.java` |
| 13 | Repo: the Android target exists. minSdk 24 and targetSdk 36 come from Flutter defaults, and the `applicationId` is still `com.example.notif`. | Src: `frontend/android/app/build.gradle`, Flutter 3.44.8 |
| 14 | Repo: device sessions die after 14 days idle or **90 days absolute**. | Src: `backend/notif/config.py` |
| 15 | Repo: only `session_store` may touch secure storage, and only `api_client` may touch dio or `Authorization`. | Src: `frontend/test/architecture_test.dart` |
| 16 | Repo: there is no request-body cap. The DRF `user` throttle (500/hour) covers every authenticated endpoint. The repo has no DB backup tooling. | Src: `Caddyfile`, `settings_base.py`, `deploy/` |

### Backfill reality: what decides how far back the export can read

The history permission removes the read cutoff (facts 1–3), but the exporter can only read what sits
in HC. Four things decide that:

1. **When each writer app started writing to HC, and whether it backfilled.** HC pulls nothing from
   any cloud. An app that connected in 2025 contributes from then on, plus whatever history it chose
   to write when it connected; that is app-specific. Google Fit's help page doesn't say whether it
   backfills (unverified).
2. **Data synced in late counts.** The cutoff tests the record's start time (fact 2). A 2023 record
   that an app wrote last week is readable with the history permission, and invisible without it.
3. **HC's own retention:** none, unless auto-delete is set to 3 or 18 months (fact 6). Deleting data
   by hand also loses it.
4. **Phone changes (Inf, high confidence).** HC lives on the device. A newer phone holds older years
   only if HC was restored from backup or export, or the writer apps re-wrote their history.

**How to check on the phone:**

1. Open Settings → Security & privacy → Privacy controls → Health Connect.
2. Go to Data and access → Browse data → a category → a type → See all entries. Tap the date for the
   calendar view, then page back to the earliest entry.
3. Manage data → Data sources and priority shows which apps write each category.
4. Manage data → Set auto-delete should read Never.

Sources: [find data](https://support.google.com/android/answer/12201872), [manage data](https://support.google.com/android/answer/12990553).

After the grant, the exporter's **coverage probe** does the same automatically before any backfill.
It shows monthly counts per type since 2015 and a forecast of MB per year.

## Options

**A. Phone-side access to HC**

| | `health` 13.3.2 ([pub.dev](https://pub.dev/packages/health)) | In-app Kotlin bridge |
|---|---|---|
| HR aggregates | `MEASUREMENTS_COUNT` only; no resting-HR aggregate (`HealthConstants.kt`) | Any metric |
| Period (local-calendar) buckets | No `aggregateGroupByPeriod` | Yes |
| Errors | `getChanges` and `getChangesToken` return `null` on any exception | Typed, mapped to `AppFailure` |
| Dependency and maintenance | Pins `connect-client:1.2.0-alpha02`; brings an iOS surface; release gap from 2026-02 to 2026-08 | Pins 1.1.0 stable; ours to maintain |
| Tests and cost | No Kotlin to write | `FakeHealthConnectClient` (`connect-testing`); about 300–500 lines of Kotlin (Inf) |

**B. Scheduling:** the `workmanager` 0.10.10 Dart isolate keeps uploads inside `api_client` (fact 15).
A native `CoroutineWorker` would duplicate the auth stack. Foreground-only sync requires opening the app.

**C. Transport:** an authenticated endpoint with idempotent upserts is the only unattended option that
also has a stable schema. A file exported on the phone needs manual moving. HC's built-in zip uses
HC's internal schema and lands in a cloud drive, which the backend does not fetch from.

**D. Raw storage layout** (measured in SQLite after `VACUUM`, with indexes; HR as a 5 s random walk)

| Layout | Bytes per HR sample | Upsert and delete by HC record id |
|---|---|---|
| Sample rows with rowid plus a unique index | 33.6 | Delete and re-insert the children |
| Sample rows, `WITHOUT ROWID` | 14.5 | Delete and re-insert the children |
| **One row per HC record, samples as JSON** (60 per record) | **9.8** (15.0 at 12 per record) | Native: one row |
| The same with the JSON compressed by zlib | 4.9 | Native, but not queryable from SQL |

## Recommendation

1. **Phone:** a Kotlin bridge as a local plugin package (`frontend/packages/hc_bridge/`) on
   connect-client 1.1.0. It exposes `status`, `requestPermissions`, `aggregate`, `readRecords` and
   `changes`. Dart orchestrates, `workmanager` schedules, and uploads go through `api_client`.
2. **Store, raw forever:** a new Django app `health` keeps one row per HC record.
   1. Columns: `hc_id` unique, type, origin, start and end as epoch ms plus zone offsets, `last_modified`.
   2. The payload goes in a JSON field: a value, HR samples, or sleep stages.
   3. The HC record is the unit of idempotency, matching `DeletionChange` (fact 9).
   4. Alongside the raw rows, store **HC hourly aggregates for Activity and Sleep**, because only HC
      knows the app-priority deduplication (fact 8).
   5. Use a separate `health.sqlite3` behind a DB router (a judgment call). A multi-hour backfill then
      cannot hold the main DB's single writer lock, it can be backed up on its own, and it can be
      copied to a laptop for DuckDB without carrying account data.
3. **Density guard:** the probe forecasts MB per year per type. Above 200 MB per year in total, the
   dense payloads are zlib-packed (lossless, about 2×). Downsampling HR to 5 s means is lossy and
   happens only with Luka's OK.
4. **Sync and backfill:**
   1. Daily: change tokens per type group, plus a re-read of the trailing 7 days for late wearable
      syncs. On token expiry, re-read 30 days and upsert by id.
   2. Backfill: a resumable WorkManager chain (unmetered network, charging), one week per type per
      step: read, upload, then advance the cursor.
   3. A heavy 3-year backfill is about 2,500 read calls (estimate below), inside one day's background
      quota.
5. **Backend endpoint:** `POST /api/health/ingest` on the bearer session.
   1. Caps: 4 MB and 5,000 records per request.
   2. Its own throttle scope, `health_ingest` (2,000/hour), so a backfill doesn't hit the 500/hour
      user throttle (fact 16).
   3. Upserts take the newer `last_modified`; deletions go by id.
   4. No outbound HTTP.
6. **Session death (fact 14):** a 401 carrying `WWW-Authenticate: Session` posts a "sign in to resume
   health sync" notification. A write-only ingest credential is worth building only if quarterly
   re-login grates.
7. **Export profiles:** an export is a profile (a query) plus a format (a writer). The command is
   `manage.py export_health --profile P --types all|steps,heart_rate --format csv|parquet --start --end --tz Europe/Belgrade`,
   which writes one long-format file per type. A download endpoint can wrap it later.

   | Profile | One row per | Source | What it drops |
   |---|---|---|---|
   | `raw` | Sample (series) or record (everything else) | Record table, samples unnested | Nothing |
   | `hourly` | Type × UTC hour: sum, or avg/min/max/n | Activity and Sleep from HC's deduplicated aggregates; HR computed from raw | Sub-hour dynamics; per-app attribution |
   | `daily` | Type × local day (sleep: noon-to-noon night) | Roll-up of `hourly`; latest value of the day for sparse types | Circadian shape, hour × weekday |

   CSV uses the stdlib. Parquet needs pyarrow, kept in a backend dependency group. It pays for itself
   on raw HR: 6.3 M rows a year is about 280 MB of CSV (about 45 B per line, Inf) against 5–19 MB of
   Parquet (0.8 B per sample measured on synthetic data, 3 B assumed for real data). Whole-hour UTC
   offsets (Belgrade is +1/+2) make the hourly-to-local-day roll-up exact.

The coverage probe takes a single call (it needs the history grant; one recent raw week per type then gives records per day):

```kotlin
val months = client.aggregateGroupByPeriod(AggregateGroupByPeriodRequest(
    metrics = setOf(StepsRecord.COUNT_TOTAL, HeartRateRecord.MEASUREMENTS_COUNT,
        SleepSessionRecord.SLEEP_DURATION_TOTAL, WeightRecord.WEIGHT_AVG),
    timeRangeFilter = TimeRangeFilter.between(LocalDateTime.of(2015, 1, 1, 0, 0), LocalDateTime.now()),
    timeRangeSlicer = Period.ofMonths(1),
)) // Months with no data are omitted. HR MEASUREMENTS_COUNT / days = samples per day.
```

**History permission flow (mandatory):**

1. Call `getSdkStatus`. If HC needs an update, deep-link to it.
2. Check `getFeatureStatus` for history and for background.
3. Show one `PermissionController.createRequestPermissionResultContract()` sheet requesting the type
   reads, history and background, as in the [androidx sample](https://github.com/androidx/androidx/blob/androidx-main/health/connect/connect-client/samples/src/main/java/androidx/health/connect/client/samples/PermissionSamples.kt).
4. Persist the grant state and `first_grant_at`.
5. **If history is granted:** run the probe, show coverage and the forecast, then start the backfill.
6. **If history is denied or unavailable:** sync still runs, and the backfill floor is
   `first_grant_at − 30 d`.
   1. Every batch carries `coverage_start`, so a gap never reads as a zero (fact 1).
   2. Settings shows "Past data off: nothing before <date>", with a button that re-requests history
      alone. A later grant starts the backfill.
   3. If the feature is unavailable, the screen points to an HC update.
7. **If background is denied:** sync and backfill run only while the app is open.

## Storage estimate

Each estimate uses measured row sizes:

| Row | Bytes |
|---|---|
| Record row | ≈ 100 B (87 B measured with a 16-byte id; +16 B for Django's 32-character UUID, Inf) |
| HR sample in JSON | 9.8 B |
| Django-default aggregate row | 139 B |

Sample rates and records per day are **assumptions until the probe runs**:

| Item | Light (phone, sparse watch) | Heavy (continuous-HR watch) |
|---|---|---|
| HR raw | 1 sample / 10 min, 1 per record: 52,560 × 120 B = 6.3 MB | 1 sample / 5 s: 6,307,200 × 10 B = 63.1 MB |
| Steps, distance, active kcal, total kcal raw | 100 records/day: 4 × 36,500 × 100 B = 14.6 MB | 500/day: 4 × 182,500 × 100 B = 73.0 MB |
| HC hourly aggregates (4 Activity + sleep) | 5 × 8,760 × 139 B = 6.1 MB | 6.1 MB |
| Sleep raw (1 session + 40 stages a night) | 365 × 1.3 KB = 0.5 MB | 0.5 MB |
| RHR, HRV, weight, body fat, SpO2, resp. rate, VO2max, exercise (≤ 1 a day) | 8 × 365 × 100 B = 0.3 MB | 0.3 MB |
| **Per year** | **≈ 28 MB** | **≈ 143 MB** |
| **Backfill of 3 years** | ≈ 83 MB | ≈ 429 MB |

Cases that move the total:

| Case | Arithmetic | Effect |
|---|---|---|
| Dense SpO2 and HRV (one reading a minute for 8 h a night) | 2 × 175,200 × 100 B | +35 MB a year |
| Pathological HR at 1 sample per second all day | 31.5 M × 10 B = 315 MB | Heavy total ≈ 395 MB a year; the guard's zlib (4.9 B) brings it to ≈ 234 MB |
| Backfill read cost, heavy | (315 k HR records + 2.19 M activity records) / 1,000 per page | ≈ 2,500 calls, under the 8,000 a day background quota |

Nothing is downsampled unless the guard fires. What the export profiles drop is listed in the profile table.

## Phased plan

1. **Phase 0, decisions with no code:**
   1. Settle the final `applicationId` with the F-Droid plan. Grants belong to the package, and a
      reinstall re-anchors the window.
   2. Set `minSdk 26` explicitly.
   3. Luka does the on-phone check above.
   4. A 1-hour spike: feature status, an HC grant to a sideloaded build (Inf: should work), and the
      bridge running in the WorkManager isolate.
2. **Phase 1, milestone M1:**
   1. Permission flow, coverage probe screen, and backfill chain.
   2. Raw sync for steps, resting HR and sleep, plus HC hourly aggregates for steps and sleep.
   3. The `health` app on `health.sqlite3`, the ingest endpoint, and `export_health` with the `raw`
      and `daily` profiles as CSV.
   4. Tests: the bridge against `FakeHealthConnectClient`. A Hypothesis property: any permutation or
      duplication of batches, and any interleaved deletions, converges to the same rows.
3. **Phase 2, breadth:** HR series, distance and kcal, HRV, weight, body fat, SpO2 and exercise
   sessions; change tokens with deletions; the `hourly` profile; Parquet.
4. **Phase 3, robustness:** a staleness `SystemEvent` in `run_due_tasks` when no batch arrives for
   72 h, the 401 notification, the density guard, and a backup of `health.sqlite3`.
5. **Phase 4, optional:** an export download in the app UI.

Interim: HC's built-in export (fact 12) is the stopgap snapshot. Takeout only covers data that
reached Google's cloud (Inf).

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| HC holds less history than the expected 2–3 years (phone change, writer apps that never backfilled) | Medium | The probe shows it before any work. Older years would need per-vendor exports, which are out of scope |
| Notif becomes the only long-term copy, with no backups (fact 16) | Certain without action | Phase 3 backup of `health.sqlite3`; keep HC auto-delete at Never |
| Data density blows the budget | Device-dependent | Probe forecast, zlib, then a downsample Luka approves |
| Reads outside the window return empty, so gaps pass for zeros | High if history is denied | `coverage_start` per batch |
| Backfill blocks the scraper's writes | Medium on a shared DB | Separate DB file and bounded batches |
| The bridge does not register in the background isolate | Medium | A local plugin package; the Phase 0 spike |
| The session hits 90 days and sync stops silently | Certain without handling | 401 notification plus the staleness event |
| A priority change alters stored HC aggregates | Low | Only 7 days are ever recomputed; raw keeps the per-app truth |

## Open questions for Luka

1. Which phone and Android version? Did you change phones in the last 3 years, and was HC restored?
   Which apps or wearables write to HC?
2. What does the on-phone check show: the earliest entries per type, and is auto-delete set to Never?
3. Which metrics matter beyond the default set?
4. Is the density guard threshold of 200 MB a year right? Is HR downsampled to 5 s acceptable if
   it is ever needed?
5. Do you agree to a separate `health.sqlite3`? Where should its backups go?
6. Is pyarrow in a backend dependency group acceptable for Parquet?
7. Is re-logging in every quarter acceptable, or should there be a write-only ingest credential?
   Do you open Notif on the phone daily?
8. Can you run HC's built-in export once, to check whether the zip is plain SQLite?
