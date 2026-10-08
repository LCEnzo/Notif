# Plan: Health Connect export

Status: **proposal, planning only** · Date: 2026-10-06 · APK distribution: see the separate F-Droid plan.

## Goal

Move Luka's Health Connect (HC) data off the phone into Notif, unattended. That includes a one-time
backfill of everything HC holds (he expects 2–3 years). Keep raw fidelity where the budget allows,
with several export profiles on top. Budget: a few hundred MB a year plus the backfill; ceiling:
never gigabytes. The read-history permission is a requirement. Out of scope: real-time sync, iOS,
writing to HC, exercise GPS routes, and analysis tooling.

## Constraints and verified facts

"Src" means read in source code; "Docs" means official docs; "Inf" means my inference.

| # | Fact | Basis |
|---|---|---|
| 1 | Without the history permission, reads **silently omit** records that start before *first HC grant − 30 days* (`Period.ofDays(30)`); only a single `readRecord` errors. This applies to `readRecords`, `aggregate*` and `getChanges`. | Src: [HealthPermission.kt](https://github.com/androidx/androidx/blob/androidx-main/health/connect/connect-client/src/main/java/androidx/health/connect/client/permission/HealthPermission.kt), AOSP `HealthConnectPermissionHelper.java` |
| 2 | The cutoff compares against the **record's own start time**, not when it was inserted. | Src: AOSP `RecordHelper.getFilterByStartAccessDateWhereClauses` |
| 3 | History permission: `android.permission.health.READ_HEALTH_DATA_HISTORY` (`HealthPermission.PERMISSION_READ_HEALTH_DATA_HISTORY`), gated by `HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_HISTORY`. | Src: HealthPermission.kt |
| 4 | The history and background features need **Android 14 (API 34) with SDK extension ≥ 13**, or the **HC APK versionCode ≥ 171302** on Android 13 and lower. | Src: [HealthConnectFeatures.kt](https://github.com/androidx/androidx/blob/androidx-main/health/connect/connect-client/src/main/java/androidx/health/connect/client/HealthConnectFeatures.kt) |
| 5 | Uninstalling the app revokes every grant, history included. A re-grant re-anchors the 30-day window. | Docs: [aggregate-data](https://developer.android.com/health-and-fitness/guides/health-connect/develop/aggregate-data), "Permissions history for a deleted app" |
| 6 | HC deletes no records on its own. Auto-delete is off (`0`) unless the user picks 3 or 18 months. | Src: AOSP `PreferencesManager`, `DailyCleanupJob`, `AutoDeleteRange.kt` |
| 7 | Background reads need `android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND` (feature `FEATURE_READ_HEALTH_DATA_IN_BACKGROUND`). | Docs: [read-data](https://developer.android.com/health-and-fitness/guides/health-connect/develop/read-data) |
| 8 | Aggregation comes in three forms: `aggregate`, `aggregateGroupByDuration` (takes `Instant`) and `aggregateGroupByPeriod` (needs `LocalDateTime`). Empty buckets are omitted. **Only Activity and Sleep are deduplicated** by the user's app priority. | Docs: aggregate-data |
| 9 | Changes API: `getChangesToken(types)` then `getChanges(token)`. `DeletionChange` carries only the id. An unused token expires within 30 days. Pages hold 1000 records by default. | Docs: [sync-data](https://developer.android.com/health-and-fitness/guides/health-connect/develop/sync-data), read-data |
| 10 | Read quotas: foreground 2,000 calls per 15 min and 16,000 per 24 h; background 1,000 per 15 min and 8,000 per 24 h. Each call costs 1. These are server-tunable defaults; the docs publish no numbers. | Src: [RateLimiter.java](https://android.googlesource.com/platform/packages/modules/HealthFitness/+/refs/heads/main/framework/java/android/health/connect/ratelimiter/RateLimiter.java) |
| 11 | `connect-client` 1.1.0 is the latest stable. It needs minSdk 26 (the HC app needs API 28), plus a rationale activity and a `VIEW_PERMISSION_USAGE` alias. | Docs: [get-started](https://developer.android.com/health-and-fitness/guides/health-connect/develop/get-started), [releases](https://developer.android.com/jetpack/androidx/releases/health-connect) |
| 12 | HC's built-in export (Android 14+) zips HC's **internal** SQLite schema on a schedule. It is unverified whether the zip is encrypted. | Docs: [backup help](https://support.google.com/android/answer/15323271); Src: AOSP `ExportManager.java` |
| 13 | Repo: the Android target exists, with Flutter-default minSdk 24 and targetSdk 36. Its id is `com.example.notif`. | Src: `frontend/android/app/build.gradle` |
| 14 | Repo: device sessions die after 14 days idle or **90 days absolute**. | Src: `backend/notif/config.py` |
| 15 | Repo: only `session_store` may touch secure storage, and only `api_client` may touch dio or `Authorization`. | Src: `frontend/test/architecture_test.dart` |
| 16 | Repo: there is no request-body cap. The DRF `user` throttle (500/hour) covers every authenticated endpoint. The repo has no DB backup tooling. | Src: `Caddyfile`, `settings_base.py`, `deploy/` |

### Backfill reality: what decides how far back the export can read

The history permission removes the cutoff, but the exporter can only read what sits in HC:

1. **When each writer app started writing to HC, and whether it backfilled.** HC pulls nothing from
   any cloud; backfilling history is each app's choice. Whether Google Fit backfills is unverified.
2. **Late-synced data counts.** The cutoff tests start time (fact 2), so a 2023 record written last
   week is readable with the history permission.
3. **Retention:** HC deletes nothing on its own (fact 6). **Luka confirmed auto-delete is off**, so
   nothing has aged out; only manual deletes lose data.
4. **Phone changes (Inf, high confidence).** A newer phone holds older years only if HC was
   restored, or the writer apps re-wrote their history.

**Check on the phone:** Settings → Security & privacy → Privacy controls → Health Connect → Data
and access → Browse data → a type → See all entries. Tap the date for the calendar view and page
back to the earliest entry. Manage data → Data sources and priority lists the writer apps.
Sources: [find data](https://support.google.com/android/answer/12201872), [manage data](https://support.google.com/android/answer/12990553).
After the grant, the exporter's **coverage probe** shows monthly counts per type since 2015 and a
forecast of MB a year, before any backfill.

## Options

**A. Phone-side access to HC**

| | `health` 13.3.2 ([pub.dev](https://pub.dev/packages/health)) | In-app Kotlin bridge |
|---|---|---|
| HR aggregates | `MEASUREMENTS_COUNT` only; no resting-HR aggregate (`HealthConstants.kt`) | Any metric |
| Period (local-calendar) buckets | No `aggregateGroupByPeriod` | Yes |
| Errors | `getChanges` and `getChangesToken` return `null` on any exception | Typed, mapped to `AppFailure` |
| Dependency and maintenance | Pins `connect-client:1.2.0-alpha02`; release gap from 2026-02 to 2026-08 | 1.1.0 stable; ours to maintain |
| Tests and cost | No Kotlin to write | `FakeHealthConnectClient`; about 300–500 lines of Kotlin (Inf) |

**B. Scheduling and transport:**

1. `workmanager` 0.10.10 runs a Dart isolate, which keeps uploads in `api_client` (fact 15). A native
   worker would duplicate the auth stack.
2. An authenticated endpoint with idempotent upserts is the only unattended path with a stable schema.
   A file on the phone needs manual moving, and HC's own zip uses HC's internal schema.

**C. Raw storage layout** (measured in SQLite after `VACUUM`, with indexes; HR as a 5 s random walk)

| Layout | Bytes per HR sample | Upsert and delete by HC record id |
|---|---|---|
| Sample rows with rowid plus a unique index | 33.6 | Delete and re-insert the children |
| Sample rows, `WITHOUT ROWID` | 14.5 | Delete and re-insert the children |
| **One row per HC record, samples as JSON** (60 per record) | **9.8** (15.0 at 12 per record) | Native: one row |
| The same with the JSON compressed by zlib | 4.9 | Native, but not queryable from SQL |

Other measured rows: an interval record is 87 B with a 16-byte id (≈ 100 B with Django's
32-character UUID, Inf), and a Django-default aggregate row is 139 B.

## Recommendation

1. **Phone:** a Kotlin bridge as a local plugin package (`frontend/packages/hc_bridge/`) on
   connect-client 1.1.0. It exposes `status`, `requestPermissions`, `aggregate`, `readRecords` and
   `changes`. Dart orchestrates and `workmanager` schedules.
2. **Store, raw forever:** a new Django app `health` keeps one row per HC record: `hc_id` unique,
   type, origin, start and end as epoch ms with zone offsets, `last_modified`, and a JSON payload
   (a value, HR samples, or sleep stages). That is the unit `DeletionChange` addresses. HC hourly
   aggregates for Activity and Sleep sit alongside, because only HC knows the app-priority
   deduplication (fact 8).
3. **A separate `health.sqlite3`** behind a DB router (a judgment call). A backfill can't hold the
   main DB's writer lock, and the file can be backed up, or copied for DuckDB, without account data.
4. **Density guard:** above a 200 MB a year forecast, the dense payloads are zlib-packed (lossless,
   about 2×). Downsampling HR to 5 s means happens only with Luka's OK.
5. **Sync:**
   1. Daily: change tokens per type group, plus a re-read of the trailing 7 days. On token expiry,
      re-read 30 days and upsert by id.
   2. Backfill: a resumable WorkManager chain (unmetered network, charging) of one-week steps
      (read, upload, then advance the cursor).
6. **Ingest:** `POST /api/health/ingest` on the bearer session.
   1. Caps of 4 MB and 5,000 records per request.
   2. Its own `health_ingest` throttle scope (2,000/hour); the 500/hour user throttle would stall a
      backfill (fact 16).
   3. Upserts take the newer `last_modified`; deletions go by id. No outbound HTTP.
7. **Session death (fact 14):** a 401 carrying `WWW-Authenticate: Session` posts a "sign in to resume
   health sync" notification. A write-only ingest credential is worth building only if quarterly
   re-login grates.
8. **Export profiles:** an export is a profile (a query) plus a format (a writer). The command is
   `manage.py export_health --profile P --types all|steps,heart_rate --format csv|parquet --start --end --tz Europe/Belgrade`,
   which writes one long-format file per type.

   | Profile | One row per | Source | What it drops |
   |---|---|---|---|
   | `raw` | Sample (series) or record (everything else) | Record table, samples unnested | Nothing |
   | `hourly` | Type × UTC hour: sum, or avg/min/max/n | Activity and Sleep from HC's deduplicated aggregates; HR from raw | Sub-hour dynamics; per-app attribution |
   | `daily` | Type × local day (sleep: noon-to-noon night) | Roll-up of `hourly`; latest value of the day for sparse types | Circadian shape, hour × weekday |

   CSV uses the stdlib. Parquet needs pyarrow in a backend dependency group. It pays for itself on
   raw HR: one year at 5 s is ≈ 280 MB of CSV (≈ 45 B per line, Inf) against 5–19 MB of Parquet
   (0.8 B per sample measured on synthetic data, 3 B assumed for real data). Belgrade's whole-hour
   offset makes the hourly-to-local-day roll-up exact.

The coverage probe is a single call. It needs the history grant; one recent raw week per type then gives records per day:

```kotlin
val months = client.aggregateGroupByPeriod(AggregateGroupByPeriodRequest(
    metrics = setOf(StepsRecord.COUNT_TOTAL, HeartRateRecord.MEASUREMENTS_COUNT,
        SleepSessionRecord.SLEEP_DURATION_TOTAL, WeightRecord.WEIGHT_AVG),
    timeRangeFilter = TimeRangeFilter.between(LocalDateTime.of(2015, 1, 1, 0, 0), LocalDateTime.now()),
    timeRangeSlicer = Period.ofMonths(1),
)) // Months with no data are omitted. HR MEASUREMENTS_COUNT / days = samples per day.
```

**History permission flow (mandatory):**

1. Call `getSdkStatus` and deep-link to an HC update if needed. Then call `getFeatureStatus` for
   history and for background.
2. Show one `PermissionController.createRequestPermissionResultContract()` sheet for the type reads,
   history and background, as in the [androidx sample](https://github.com/androidx/androidx/blob/androidx-main/health/connect/connect-client/samples/src/main/java/androidx/health/connect/client/samples/PermissionSamples.kt).
   Persist the grant state and `first_grant_at`.
3. **If history is granted:** run the probe, show coverage and the forecast, then start the backfill.
4. **If history is denied or unavailable:** sync still runs, and the backfill floor is
   `first_grant_at − 30 d`. Every batch carries `coverage_start`, so a gap never reads as a zero
   (fact 1). Settings shows "Past data off: nothing before <date>", with a button that re-requests
   history alone. If the feature is unavailable, the screen points to an HC update.
5. **If background is denied:** sync and backfill run only while the app is open.

## Storage estimate

Each estimate uses the measured row sizes from options C. Sample rates and record counts are
**assumptions until the probe runs**.

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
| Pathological HR at 1 sample per second all day | 31.5 M × 10 B = 315 MB | Heavy total ≈ 395 MB a year; the guard's zlib brings it to ≈ 234 MB |
| Heavy backfill read cost | (315 k HR records + 2.19 M activity records) / 1,000 per page | ≈ 2,500 calls, under the 8,000 a day background quota |

## Phased plan

1. **Phase 0, decisions:**
   1. The app id is **`com.lcenzo.notif`** (confirmed). Switch to it before the first HC grant,
      because grants belong to the package and a reinstall re-anchors the window (fact 5).
   2. Set `minSdk 26` explicitly.
   3. Luka checks the earliest entries on the phone.
   4. A 1-hour spike: feature status, an HC grant to a sideloaded build (Inf: should work), and the
      bridge running in the WorkManager isolate.
2. **Phase 1, M1:**
   1. Permission flow, coverage probe, and backfill.
   2. Raw sync for steps, resting HR and sleep, plus HC hourly aggregates for steps and sleep.
   3. The `health` app on `health.sqlite3`, the ingest endpoint, and `export_health` with `raw` and
      `daily` profiles as CSV.
   4. Tests: the bridge against `FakeHealthConnectClient`. A Hypothesis property: any permutation or
      duplication of batches, and any interleaved deletions, converges to the same rows.
3. **Phase 2, breadth:** HR series, distance and kcal, HRV, weight, body fat, SpO2 and exercise
   sessions; change tokens with deletions; the `hourly` profile; Parquet.
4. **Phase 3, robustness:** a staleness `SystemEvent` in `run_due_tasks` after 72 h without a batch,
   the 401 notification, the density guard, and a backup of `health.sqlite3`.
5. **Phase 4, optional:** an export download in the app UI.

Interim: HC's built-in export (fact 12) is the stopgap snapshot. Takeout only covers data that
reached Google's cloud (Inf).

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| HC holds less history than the expected 2–3 years (phone change, writer apps that never backfilled) | Medium | The probe shows it first. Older years would need per-vendor exports, which are out of scope |
| Notif becomes the only long-term copy, with no backups (fact 16) | Certain without action | Phase 3 backup of `health.sqlite3` |
| Data density blows the budget | Device-dependent | Probe forecast, zlib, then a downsample Luka approves |
| Gaps pass for zeros when history is denied | High in that case | `coverage_start` per batch |
| Backfill blocks the scraper's writes | Medium on a shared DB | Separate DB file and bounded batches |
| The bridge does not register in the background isolate | Medium | A local plugin package; the Phase 0 spike |
| The session hits 90 days and sync stops silently | Certain without handling | 401 notification plus the staleness event |

## Open questions for Luka

1. Which phone and Android version? Did you change phones in the last 3 years, and was HC restored?
   Which apps or wearables write to HC?
2. What does the on-phone check show for the earliest entries per type?
3. Which metrics matter beyond the default set?
4. Is the density guard threshold of 200 MB a year right? Is HR downsampled to 5 s acceptable if it
   is ever needed?
5. Do you agree to a separate `health.sqlite3`? Where should its backups go?
6. Is pyarrow in a backend dependency group acceptable for Parquet?
7. Is re-logging in every quarter acceptable, or should there be a write-only ingest credential?
8. Can you run HC's built-in export once, to check whether the zip is plain SQLite?
