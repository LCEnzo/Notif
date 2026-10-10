# Health Connect ingest and export

The backend half of Phase 1 of [`docs/plans/health-connect-export.md`](../plans/health-connect-export.md): where Health Connect (HC) data is stored, the contract the phone uploads through, and the `export_health` command.

## Storage

The `health` app keeps its tables in the main database.

The plan recommended a separate `health.sqlite3` behind a database router, so that a backfill could not hold the main writer lock. Luka decided against it on 2026-10-08, after a two-file version was built. For one user the lock argument was weak: a worst-case batch of 5,000 records takes about 1.2 s end to end, of which only the 0.3–0.5 s of applying holds the lock (measured on Windows). The costs of two files were real:

1. No foreign key or cascade could reach the user table, so deletion needed signal plumbing, an on-commit purge and an orphan sweep.
2. Every `migrate` had to run twice.
3. The readiness probe, the test setup and the API fuzzer each had to know about a second database.

| Table | One row per | Key |
|---|---|---|
| `HealthRecord` | HC record, current version | `owner`, `hc_id` |
| `HealthDeletion` | Deleted HC id (tombstone, kept forever) | `owner`, `hc_id` |
| `HealthAggregate` | Metric and UTC hour, the last answer HC gave | `owner`, `metric`, `bucket_start_ms` |
| `HealthSource` | Distinct (data origin, recording method, device) | Shared by records, stored once |
| `HealthIngestBatch` | Accepted batch (a log) | `owner`, `received_at` |

`owner` is a foreign key to the user with `on_delete=CASCADE`, so a hard-deleted user takes their rows along. `HealthSource` exists for the size budget: the origin, method and device would otherwise add about 90 bytes to every record, roughly 200 MB a year at the plan's heavy profile. Measured after VACUUM, a steps record costs about 157 bytes with its indexes.

## Rules

`health.ingest.apply_batch` applies one batch atomically and logs it. Applying batches in any order, any number of times, leaves the same rows, so a client may always retry.

1. **Versions.** Per `hc_id` within the owner's rows, the version with the newest `last_modified_ms` is kept. Equal timestamps with different content resolve by content, so every order picks the same one.
2. **Deletions.** A deletion removes every version of its id with `last_modified_ms <= observed_at_ms`, including versions that arrive later in another batch. A newer version still comes back, as it does when an app deletes and rewrites a record under the same client id. The tombstone keeps the latest `observed_at_ms`.
3. **The client's side of rule 2.** `observed_at_ms` is when the phone read the change, on the clock HC stamps `last_modified` with. Within one `getChanges` stream, the client keeps the last change per id: a deletion followed by an upsert of the same id must not be sent as a deletion.
4. **Aggregates.** Each hour of an aggregate window is an answer: a bucket's value, or "HC had nothing" for an hour HC omitted. Per metric and hour, the answer with the newest `computed_at_ms` is kept; on a tie a value beats nothing, then the larger value wins. A re-aggregation therefore clears an hour whose records were deleted in HC.
5. **Coverage.** Silence before the batch's `coverage_start_ms` means nothing, since HC hid that data, so those hours are not stored. A bucket HC did return is stored wherever it lies.

`test_properties.py` checks rules 1, 2, 4 and 5 against a reference model under random order and duplication; `test_ingest.py` pins their exact boundaries.

## Endpoint

`POST /api/v1/health/ingest/`, operation `health_ingest` in `backend/openapi.json`. JSON only (anything else is 415). The phone authenticates with its device session, `Authorization: Session <token>`; a dead token is a 401 with `WWW-Authenticate: Session`. Requests draw on their own `health_ingest` throttle scope, 2000 an hour, instead of the general 500/hour budget a backfill would exhaust; a 429 carries `Retry-After`. The endpoint makes no outbound HTTP.

The body is `coverage_start_ms` (required; the earliest instant HC let the phone read, or null with the history permission) and five optional lists: `steps`, `resting_heart_rate`, `sleep_session`, `deletions` and `aggregate_windows`. Times are integer epoch milliseconds, zone offsets integer seconds or null. Every record carries `hc_id` (HC `metadata.id`), `data_origin`, `last_modified_ms`, `recording_method` and `device` (null, or `{type, manufacturer, model}`); HC's integer constants are sent as the lower-snake names in the schema's enums, and a constant the contract does not know maps to `unknown`. Steps and sleep carry `start_ms`, `start_offset_s`, `end_ms` (exclusive) and `end_offset_s`; resting heart rate carries `time_ms` and `offset_s`. Sleep stages must lie within their session. An aggregate window covers whole UTC hours, at most 31 days, with one bucket per hour HC returned.

| Bound | Value | Beyond it |
|---|---|---|
| Body | 4,194,304 bytes, checked against `Content-Length` and while reading | 413 |
| Items | 5,000 records, deletions and aggregate-window hours together | 400 |
| Values | Looser than HC's own: times 0 to 2100, offsets ±18 h, strings 255 (title and notes 10,000), stages 10,000 per session | 400 |

JSON types are strict: an integer sent as a string, a float or a boolean is a 400, and so is any key the contract does not declare, including a record type this server does not support yet. A 200 carries `{batch_id, records_written, records_deleted, aggregates_written}`. A 400 carries field errors, with a failing list item keyed by its index (`{"steps": {"1": {...}}}`).

## Export

```bash
uv run python manage.py export_health --user LCEnzo --profile daily --output-dir exports/ \
	[--types all|steps,sleep_session] [--start 2026-01-01] [--end 2026-03-31] [--tz Europe/Belgrade]
```

The command writes one CSV per record type, `<profile>-<type>.csv`: UTF-8, LF line ends, a header row, blank cells for nulls. Each file is written through a `.partial` file, so an interrupted export leaves no truncated CSV. `--start` and `--end` are local dates in `--tz`, both inclusive: `raw` selects by each record's start, `daily` by the window's date. Rows stream from the database 2,000 at a time.

**`raw`** has one row per record, or per stage for sleep; a session without stages gets one row with blank stage columns. Every file starts with `hc_id, data_origin, recording_method, device_type, device_manufacturer, device_model, start_utc, start_local, start_offset_s, end_utc, end_local, end_offset_s, last_modified_utc`. `*_local` is the instant in `--tz`, with the right offset on each side of a DST change; `*_offset_s` is the offset HC recorded. The type columns are `count`, `beats_per_minute`, or `title, notes, stage, stage_start_utc, stage_start_local, stage_end_utc, stage_end_local`.

**`daily`** has the columns `date, type, value, unit, window_start_utc, window_end_utc, n, partial`.

| Type | Window | `value` | `n` | `partial` |
|---|---|---|---|---|
| `steps` | Local day | Sum of HC's hourly `steps_count_total` | Hours with a value | Some hour of the window has no stored answer |
| `sleep_session` | Noon to noon, dated by the wake-up day | Sum of hourly `sleep_duration_total`, in exact decimal seconds | Hours with a value | As `steps` |
| `resting_heart_rate` | Local day | The latest reading; a tie on time goes to the newer `last_modified`, then the larger id | Readings that day | The day starts before the earliest `coverage_start_ms` of any batch; never once a batch had the history permission |

A window with no stored answer at all has no row: a gap. A complete window where HC had nothing has `value` 0 and `partial` false: a real zero. Local days run 23 or 25 hours across DST changes, which `window_*_utc` shows. Each hourly bucket goes to the window containing its start, which is exact for whole-hour zones such as `Europe/Belgrade`.

## Deleting an account

A user's health rows go with the account (`backend/health/lifecycle.py`).

1. **Hard delete** (`actually_delete`, the admin's bulk delete) cascades through the `owner` foreign keys.
2. **Soft delete** (`User.delete`, which `DELETE /api/v1/accounts/users/{id}/` calls) only sets `date_deleted`, so a `post_save` hook deletes the rows inside that same transaction. A deletion that rolls back keeps them, and no state exists where the account is gone but its rows remain.
3. **Deactivation** (`is_active` false, no `date_deleted`) keeps them.
4. **A request already past authentication** cannot store a batch for an account deleted meanwhile. `apply_batch` checks, first thing in its transaction, that the owner is active and undeleted. Transactions are `IMMEDIATE`, so the check runs under the write lock: a soft delete either committed before it, and the check sees it, or waits and then deletes the batch too. The request then gets a 401 with `WWW-Authenticate: Session`.

`HealthSource` rows are shared across owners and stay.
