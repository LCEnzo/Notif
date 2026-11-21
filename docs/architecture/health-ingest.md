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
