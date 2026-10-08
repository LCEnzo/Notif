# Health Connect sync, phone side

The phone half of Phase 1 of [`docs/plans/health-connect-export.md`](../plans/health-connect-export.md). The phone reads Health Connect (HC) and uploads to `POST /api/v1/health/ingest/`, whose contract is [`health-ingest.md`](health-ingest.md). This page covers what the phone reads, when it reads it, and what it keeps between runs.

## Scope

| | Types |
|---|---|
| Read permission requested | Every HC record type in connect-client 1.1.0 (41 types, 38 permissions), except exercise routes, which have their own consent flow. Skin temperature, planned exercise and mindfulness are requested only where HC offers the feature. Also `READ_HEALTH_DATA_HISTORY` and `READ_HEALTH_DATA_IN_BACKGROUND`. |
| Uploaded | Steps, resting heart rate and sleep sessions with stages, plus HC's hourly `steps_count_total` and `sleep_duration_total`. |
| Probed only | Everything else readable: the coverage probe says which types hold data, to pick Phase 2's types. |

Android 13 and older get no special handling. The target phone runs Android 16 (HyperOS).

## Components

| Piece | Where | Does |
|---|---|---|
| Bridge | `frontend/packages/hc_bridge/` | Kotlin on `androidx.health.connect:connect-client` 1.1.0 behind a method channel. Typed results, typed errors (`HcErrorCode`), never null for a failure. Unknown HC constants map to `unknown`. |
| Mapping and batching | `lib/services/health/ingest_items.dart`, `batching.dart` | Bridge records to the generated request types, checked against every contract bound; packing under 5,000 items and 4 MiB. |
| State | `lib/services/health/sync_store.dart` | Everything kept between runs, through `PreferenceStore` under `health.v1.*`. |
| Engine | `lib/services/health/sync_engine.dart` | The sync, the backfill and the coverage probe. |
| Scheduling | `lib/services/health/scheduler.dart` | WorkManager tasks and the background isolate's wiring. |
| Screen | `lib/services/health/health_service.dart`, `lib/screens/health.dart` | Status, grants, coverage, backfill, last sync, Sync now, background reliability. |

### Bridge operations

| Method | Answer |
|---|---|
| `status` | SDK status (`available`, `unavailable`, `update_required`), each gated feature's status, granted permissions |
| `requestPermissions(set)` | Shows HC's sheet; returns what is granted afterwards. Needs a foreground activity. |
| `readRecords(type, start, end, page)` | One page of steps, resting HR or sleep records in `[start, end)` |
| `aggregateHourly(metric, start, end)` | `aggregateGroupByDuration` by hour over whole UTC hours, at most 744 |
| `changesToken(types)`, `changes(token)` | HC's changes API. A page is reordered so "the last change per id wins" holds: Android 14+ lists upserts before deletions, so a deletion whose id is also upserted in the page is dropped. |
| `coverageProbe(types)` | Per type: months with data, or a bounded record count (below) |
| `batteryOptimizationExempt`, `requestBatteryOptimizationExemption` | `PowerManager.isIgnoringBatteryOptimizations`; the system exemption dialog |

## The sync

The daily periodic task and "Sync now" run the same method, `HealthSyncEngine.runSync`; only the recorded trigger differs.

1. Read HC's status and record grants. `first_grant_at` is set the first time any data read is granted and cleared when none is, because HC re-anchors its 30-day window on a fresh grant. An observed time is never earlier than the real grant, so it errs towards a gap, never a false zero.
2. With a saved changes token for exactly the readable uploaded types, pull every page (at most 200). The last change per id wins across pages (contract rule 3). A deletion carries `observed_at_ms`, the phone's clock just before that `getChanges` call. Without a token, take one first, so changes during the reads land in the next run.
3. Re-read the trailing 7 days of records, reaching 2 more days back so records straddling the edge are read whatever HC's filter semantics are, plus the hourly aggregates over the 7 days. Records are de-duplicated by id, newest `last_modified` wins.
4. Upload the batches. Every batch carries `coverage_start_ms`: null with the history grant, otherwise `first_grant_at − 30 days`.
5. Only after every batch landed, save the next token. A run that fails part-way re-pulls the same changes; the server is idempotent.

| Event | Handling |
|---|---|
| Token expired (`changesTokenExpired`) | New token, and step 3 re-reads 30 days instead of 7 |
| `getChanges` fails with `remote` or `io` | The run continues without changes, keeps the token, and reports `partial` |
| A record or window the contract would refuse | Left out and counted as skipped, so one odd record never stalls the sync |
| HC rate limit, IO, binder, network, 5xx, 429 | `failed`, retryable: WorkManager backs off |
| 401 with `WWW-Authenticate: Session` | Terminal. The token stays, the run records "signed out", and later runs touch neither HC nor the server until a sign-in clears the marker (`HealthService` does, on a transition from signed-out or expired to signed-in). The screen shows the state beside the last successful sync. No prompt or notification. |

### Backfill

An hourly WorkManager task, only on an unmetered network while charging, started from the screen. It walks a cursor back one week per step: read, upload, then save the cursor. The floor is the coverage probe's earliest month with data for an uploaded type, with the history grant; without it, `first_grant_at − 30 days`. A run stops after 52 steps or 8 minutes and continues next time; once the cursor reaches the floor the task unschedules itself.

### Coverage probe

Run after the first grant and from the screen. It probes every readable type:

1. Types whose aggregate shows monthly presence faithfully (steps, distance, active calories, floors, elevation, hydration, heart rate measurement count, resting HR, weight, height, power, exercise duration, sleep duration, wheelchair pushes): one `aggregateGroupByPeriod` per calendar year since 2015, all metrics in one request, and the months that have a value.
2. Everything else: records counted over 2015 to now, at most 10 pages of 1,000, reported as "at least" past that. Blood pressure, cadence, speed and nutrition are here because their aggregates fall back to client-side record reads on older SDK extensions. Total and basal calories are here because HC synthesizes them from weight and height.

It also reads the last 7 days of the uploaded types and forecasts MB a year, with the plan's row sizes (100 B a record, 30 B a sleep stage, 139 B an aggregate hour).

## State

| Key (`health.v1.` prefix) | Holds |
|---|---|
| `changes_token`, `changes_token_types` | The token and the sorted type set it covers; a grant change makes it unusable |
| `first_grant_at_ms`, `granted_permissions`, `grant_observed_at_ms` | Grant bookkeeping |
| `backfill_requested`, `backfill_start_ms`, `backfill_cursor_ms` | Backfill progress |
| `last_sync`, `last_backfill`, `last_sync_success_ms` | The last run per kind (JSON) and the last successful sync |
| `coverage` | The last probe and forecast (JSON) |
| `session_expired_at_ms`, `sync_requested_at_ms` | The signed-out marker; a pending Sync now |

A malformed JSON value reads as `CorruptLocalStateException`, classified as `corruptLocalState`.

### Two isolates, no lock

The UI isolate and the WorkManager isolate share this store; each calls `reload()` before reading what the other wrote. Runs are not serialized. WorkManager never runs a unique task twice at once. A periodic sync and a Sync now that overlap both upload, which the server makes idempotent. Either may save its token last, and both are valid: a token is saved only after its run uploaded every change before it, so the worst case is re-pulling changes, never skipping them. The backfill cursor has one writer.

## Background isolate

`healthCallbackDispatcher` re-creates only what a sync needs: `AppSettingsController` for the backend URL, the stored `SessionCredential` handed to `configureApiAuth` (no `AuthService`), and the store. Requests still go through `api_client`, so origin pinning and the credential rules hold. A missing credential records "signed out" without a request. Architecture tests keep the bridge behind `lib/services/health/`, WorkManager and the second credential wiring in `scheduler.dart`, and health state off raw `shared_preferences`.

## Background reliability

HyperOS stops background work of apps it has not been told to leave alone. The screen shows whether Notif is exempt from battery optimization and offers Android's exemption dialog (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, acceptable for a sideloaded app). HyperOS's Autostart switch cannot be read or set by an app, so the screen says where it is. Without both, the daily job may run late or not at all. A device session dies after 14 idle days, so a fortnight of skipped jobs ends in the signed-out state.

## Not verifiable off the phone

Grants to a sideloaded package; the bridge registering in the WorkManager engine; HyperOS letting the jobs run; HC's real filter semantics at window edges; the probe's quota cost on a large store; the rationale screen and the `VIEW_PERMISSION_USAGE` alias opening from HC's settings.
