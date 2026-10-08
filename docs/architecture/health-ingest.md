# Health Connect ingest and export

The backend half of Phase 1 of [`docs/plans/health-connect-export.md`](../plans/health-connect-export.md): where Health Connect (HC) data is stored, the contract the phone uploads through, and the `export_health` command. `backend/openapi.json` is the machine-readable contract (operation `health_ingest`); this page adds the rules a schema cannot express.

## Storage

The `health` app keeps its tables in their own SQLite file. `HealthRouter` (`backend/health/routers.py`) sends the app's reads, writes and migrations to the `health` alias and keeps every other app off it.

| Setting | Default | Notes |
|---|---|---|
| `HEALTH_SQLITE_PATH` | `health.sqlite3` beside `SQLITE_PATH` | In production that is `/app/data/health.sqlite3`, on the `backend_data` volume. Config refuses the same file as `SQLITE_PATH`, since the two aliases would share `django_migrations`. |

`migrate` handles one database per run, so every place that migrates runs it twice: `migrate` and `migrate --database health`. That covers `backend/docker-entrypoint.sh`, both READMEs and `deploy.md`. pytest-django creates the second test database for any test that declares `databases = {"default", "health"}`.

Users live in the other file, so rows carry `owner_id` without a foreign key. Ids are never reused: Django's SQLite primary keys are `AUTOINCREMENT`. `/api/v1/monitoring/status/` reports `db: down` unless both files open and answer `SELECT 1`.

To fold the store back into `db.sqlite3`, delete the `health` alias and `DATABASE_ROUTERS` from `settings_base.py`, then copy the rows across. The code only ever names the alias through `router.db_for_write(...)`.

| Table | One row per | Key |
|---|---|---|
| `HealthRecord` | HC record, current version | `owner_id`, `hc_id` |
| `HealthDeletion` | Deleted HC id (tombstone, kept forever) | `owner_id`, `hc_id` |
| `HealthAggregate` | Metric and UTC hour, last answer HC gave | `owner_id`, `metric`, `bucket_start_ms` |
| `HealthSource` | Distinct (data origin, recording method, device) | Shared by records, stored once |
| `HealthIngestBatch` | Accepted request (a log) | `coverage_start_ms` and item counts |

`HealthSource` exists for the size budget: an origin such as `com.google.android.apps.fitness`, a recording method and a device would otherwise add roughly 90 bytes to every record.

## Endpoint

`POST /api/v1/health/ingest/`, JSON only (`Content-Type: application/json`; anything else is 415).

1. **Auth.** The existing device session. The phone sends `Authorization: Session <token>`; a cookie session also works and needs `X-CSRFToken`. A dead token is a 401 with `WWW-Authenticate: Session`.
2. **Throttle.** Scope `health_ingest`, 2000 requests an hour per user. It replaces the general 500/hour `user` budget for this endpoint, which a backfill would exhaust. A 429 carries `Retry-After` in seconds.
3. **Atomic and idempotent.** A batch applies entirely or not at all. Replaying it, or sending batches in any order, any number of times, leaves the same rows. A retry after a timeout is always safe.
4. **No outbound HTTP.** The endpoint only writes the health file.

### Body

All times are integer epoch milliseconds and all zone offsets integer seconds (HC's `ZoneOffset.totalSeconds`), or null where HC has none. Every list is optional and may be empty; `coverage_start_ms` is required.

| Key | Content |
|---|---|
| `coverage_start_ms` | The earliest instant HC let the phone read when it built this batch: the first grant minus 30 days without `READ_HEALTH_DATA_HISTORY`, null with it. |
| `steps` | `StepsRecord`s |
| `resting_heart_rate` | `RestingHeartRateRecord`s |
| `sleep_session` | `SleepSessionRecord`s, stages included |
| `deletions` | `{hc_id, observed_at_ms}` per id from a `DeletionChange` |
| `aggregate_windows` | One `aggregateGroupByDuration` answer per metric over whole UTC hours |

Fields every record carries:

| Field | From HC | Notes |
|---|---|---|
| `hc_id` | `metadata.id` | UUID string |
| `data_origin` | `metadata.dataOrigin.packageName` | |
| `last_modified_ms` | `metadata.lastModifiedTime` | Decides which version wins |
| `recording_method` | `metadata.recordingMethod` | `unknown`, `actively_recorded`, `automatically_recorded`, `manual_entry` |
| `device` | `metadata.device` | null, or `{type, manufacturer, model}`; `type` is HC's `Device.TYPE_*` in lower snake case (`watch`, `phone`, `ring`, ...); an empty manufacturer or model reads back as null |

Per type:

| Type | Times | Value fields |
|---|---|---|
| `steps` | `start_ms`, `start_offset_s`, `end_ms` (exclusive, after start), `end_offset_s` | `count` |
| `resting_heart_rate` | `time_ms`, `offset_s` (instantaneous) | `beats_per_minute` |
| `sleep_session` | as `steps` | `title`, `notes` (null or string), `stages`: `[{start_ms, end_ms, stage}]` within the session; `stage` is HC's `STAGE_TYPE_*` in lower snake case (`light`, `deep`, `rem`, `awake`, ...) |

The bridge maps HC's integer constants to these names. A constant this contract does not know (a future HC release) maps to `unknown`, so a sync never stalls on it.

An aggregate window is `{metric, start_ms, end_ms, computed_at_ms, buckets}`. `metric` is `steps_count_total` (`StepsRecord.COUNT_TOTAL`, a count) or `sleep_duration_total` (`SleepSessionRecord.SLEEP_DURATION_TOTAL`, milliseconds). `start_ms` and `end_ms` fall on UTC hours. Each bucket is `{start_ms, value, data_origins}` for one hour inside the window, as HC returned it.

### Rules

1. **Versions.** Per `hc_id` within the caller's account, the version with the newest `last_modified_ms` is kept. Equal timestamps with different content resolve by content, so every order picks the same one.
2. **Deletions.** A deletion removes every version of its id with `last_modified_ms <= observed_at_ms`, including versions that arrive later in another batch. A newer version still comes back, as it does when an app deletes and rewrites a record with the same client id. The tombstone keeps the latest `observed_at_ms`.
3. **The client's side of rule 2.** `observed_at_ms` is when the phone read the change, on the clock HC stamps `last_modified` with. Within one `getChanges` stream, the client keeps the last change per id: a deletion followed by an upsert of the same id must not be sent as a deletion.
4. **Aggregates.** Each hour of a window is an answer: a bucket's value, or "HC had nothing" for an hour without one, which HC omits. Per metric and hour, the answer with the newest `computed_at_ms` is kept; on a tie a value beats nothing, then the larger value wins. A re-aggregation therefore clears an hour whose records were deleted in HC.
5. **Coverage.** Silence before `coverage_start_ms` means nothing, since HC hid that data, so those hours are not stored. A bucket HC did return is stored wherever it lies. The batch log keeps every `coverage_start_ms`.

### Limits

| Bound | Value | Answer beyond it |
|---|---|---|
| Body | 4,194,304 bytes (4 MiB), checked against `Content-Length` and while reading | 413 |
| Items per batch | 5,000, counting records of every type, deletions and aggregate-window hours together | 400 |
| Window length | 744 hours (31 days) | 400 |
| Stages per session | 10,000 | 400 |
| Times | 0 to 4,102,444,800,000 (2100-01-01) | 400 |
| Zone offsets | ±64,800 s | 400 |
| `count` | 0 to 10,000,000 | 400 |
| `beats_per_minute` | 0 to 1,000 | 400 |
| Bucket `value` | 0 to 1,000,000,000 | 400 |
| Strings | 255 characters; `title` and `notes` 10,000 | 400 |
| `data_origins` per bucket | 100 | 400 |

The value bounds are looser than HC's own on purpose: a record HC accepted must not be refused here, or one odd record would stall a backfill. JSON types are strict: an integer sent as a string, a float or a boolean is a 400, and so is any key the contract does not declare, including a record type this server does not support yet.

### Answers

| Status | Body |
|---|---|
| 200 | `{batch_id, records_written, records_ignored, records_deleted, aggregates_written, aggregates_ignored}` |
| 400 | Field errors. A failing list item is keyed by its index: `{"steps": {"1": {"count": ["..."]}}}`. A batch over the item cap or a body that does not parse answers `{"non_field_errors": [...]}` or `{"detail": ...}`. |
| 401, 403, 413, 429 | `{"detail": "..."}` |

## Export

```bash
uv run python manage.py export_health --user LCEnzo --profile daily --output-dir exports/ \
	[--types all|steps,sleep_session] [--start 2026-01-01] [--end 2026-03-31] [--tz Europe/Belgrade] [--format csv]
```

The command writes one file per record type, `<profile>-<type>.csv`: UTF-8, LF line ends, a header row, and blank cells for nulls. It writes each file through a `.partial` file, so an interrupted export leaves no truncated CSV. `--start` and `--end` are local dates in `--tz`, both inclusive; `raw` selects by each record's start, `daily` by the window's date. Rows stream from the database in chunks of 2,000.

### `raw`

One row per record, or per stage for sleep; a session without stages gets one row with blank stage columns. Every file starts with `hc_id, data_origin, recording_method, device_type, device_manufacturer, device_model, start_utc, start_local, start_offset_s, end_utc, end_local, end_offset_s, last_modified_utc`. `*_utc` is ISO 8601 with `Z`. `*_local` is the same instant in `--tz`, which shows the right offset on both sides of a DST change. `*_offset_s` is the offset HC recorded, which may differ from `--tz`. Instantaneous types leave the `end_*` columns blank. The type columns are `count`, `beats_per_minute`, or `title, notes, stage, stage_start_utc, stage_start_local, stage_end_utc, stage_end_local`.

### `daily`

Every file has the columns `date, type, value, unit, window_start_utc, window_end_utc, n, partial`.

| Type | Window | `value` | `n` | `partial` |
|---|---|---|---|---|
| `steps` | Local day | Sum of HC's hourly `steps_count_total` (`count`) | Hours with a value | Some hour of the window has no stored answer |
| `sleep_session` | Noon to noon, dated by the day it ends (the wake-up date) | Sum of hourly `sleep_duration_total`, in seconds (`s`, exact decimals) | Hours with a value | As `steps` |
| `resting_heart_rate` | Local day | The latest reading (`bpm`); a tie on time goes to the newer `last_modified`, then the larger id | Readings that day | The day starts before the earliest `coverage_start_ms` any batch reported; never with a batch that had the history permission |

A window with no stored answer at all has no row: that is a gap. A complete window where HC had nothing gets `value` 0 with `partial` false: that is a real zero. Local days run 23 or 25 hours across DST changes, which `window_*_utc` shows. Each hourly bucket goes to the window containing its start. That is exact for a zone with whole-hour offsets such as `Europe/Belgrade`; in a half-hour zone, buckets straddle window boundaries.

## Deleting an account

Deleting a user deletes that user's `HealthRecord`, `HealthDeletion`, `HealthAggregate` and `HealthIngestBatch` rows (`backend/health/owners.py`). Users are soft-deleted (`User.delete`, which the API's `DELETE /api/v1/accounts/users/{id}/` calls, sets `date_deleted`) or hard-deleted (`actually_delete`, the admin's bulk delete). Either kind schedules the purge with `transaction.on_commit` on the user's database, so a deletion that rolls back keeps the rows. Deactivation (`is_active` false, no `date_deleted`) keeps them. `HealthSource` rows are shared across owners and stay.

A purge that fails after the deletion committed is logged at ERROR, which makes it a `SystemEvent` naming the user id. `uv run python manage.py purge_health_orphans` then deletes the rows of every owner the default user manager no longer returns, which covers soft- and hard-deleted users.

## Known limits

1. **One phone per account.** Two phones would each report hourly aggregates for the same hours, and the later computation would win, hour by hour.
2. **Purging a large account holds the health write lock.** The purge deletes each table in one transaction, so ingest from other accounts waits behind it, up to the 20 s busy timeout.
3. **No backup.** `scripts/backup-db.sh` and the ops backup endpoint cover `db.sqlite3` only (plan Phase 3).
4. **Tombstones are never collected.** They grow by one row per deleted id. Collecting them would let a stale batch replayed late resurrect a record.
5. **Overlapping sleep stages are accepted.** Only stages outside the session are refused.
6. **The readiness probe does not see a missing migration.** A health file that was never migrated still answers `SELECT 1`; ingest then fails with 500s.
