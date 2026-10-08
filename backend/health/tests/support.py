"""Builders for ingest values, owners, and a readable dump of an owner's store."""

from datetime import UTC, datetime
from itertools import count
from typing import Any
from uuid import UUID

from accounts.models import User
from health.ingest import HOUR_MS, AggregateBucket, AggregateWindow, Deletion, IngestBatch, RecordVersion, Source
from health.models import AggregateMetric, HealthAggregate, HealthDeletion, HealthRecord, RecordType

HOUR = HOUR_MS
ORIGIN = "com.google.android.apps.fitness"
SOURCE = Source(ORIGIN, "automatically_recorded", None, None, None)
_owners = count()


def owner() -> int:
	"""A fresh user's id; health rows need a real owner."""
	n = next(_owners)
	return User.objects.create(username=f"health-owner-{n}", email=f"health-owner-{n}@example.com").pk


def ms(year: int, month: int, day: int, hour: int = 0, minute: int = 0) -> int:
	"""Epoch ms of a UTC wall time, e.g. ``ms(2026, 3, 29, 1)``."""
	return int(datetime(year, month, day, hour, minute, tzinfo=UTC).timestamp()) * 1000


def uid(n: int) -> UUID:
	return UUID(int=n)


def steps_version(
	hc_id: UUID, *, last_modified: int, count: int = 100, start: int = 0, end: int = 60_000, source: Source = SOURCE
) -> RecordVersion:
	return RecordVersion(hc_id, RecordType.STEPS, source, start, 3_600, end, 3_600, last_modified, {"count": count})


def window(
	metric: AggregateMetric, start: int, hours: int, computed_at: int, values: dict[int, int]
) -> AggregateWindow:
	"""``values`` maps an hour offset within the window to its value; other hours had nothing."""
	buckets = tuple(
		AggregateBucket(start + offset * HOUR, value, (ORIGIN,)) for offset, value in sorted(values.items())
	)
	return AggregateWindow(metric, start, start + hours * HOUR, computed_at, buckets)


def batch(*items: RecordVersion | Deletion | AggregateWindow, coverage_start_ms: int | None = None) -> IngestBatch:
	return IngestBatch(
		coverage_start_ms=coverage_start_ms,
		records=tuple(item for item in items if isinstance(item, RecordVersion)),
		deletions=tuple(item for item in items if isinstance(item, Deletion)),
		aggregate_windows=tuple(item for item in items if isinstance(item, AggregateWindow)),
	)


def store(owner_id: int) -> dict[str, Any]:
	"""Everything the store holds for one owner, without row ids."""
	records = {
		row.hc_id: (
			row.record_type,
			Source.of(row.source).key(),
			row.start_ms,
			row.start_offset_s,
			row.end_ms,
			row.end_offset_s,
			row.last_modified_ms,
			row.payload,
		)
		for row in HealthRecord.objects.filter(owner_id=owner_id).select_related("source")
	}
	tombstones = dict(HealthDeletion.objects.filter(owner_id=owner_id).values_list("hc_id", "observed_at_ms"))
	aggregates = {
		(row.metric, row.bucket_start_ms): (row.value, tuple(row.data_origins), row.computed_at_ms)
		for row in HealthAggregate.objects.filter(owner_id=owner_id)
	}
	return {"records": records, "tombstones": tombstones, "aggregates": aggregates}


# ── wire payloads ────────────────────────────────────────────


def device_wire(**overrides: Any) -> dict[str, Any]:
	return {"type": "watch", "manufacturer": "Google", "model": "Pixel Watch 2", **overrides}


def steps_wire(n: int, **overrides: Any) -> dict[str, Any]:
	start = ms(2026, 10, 1, 8) + n * 60_000
	return {
		"hc_id": str(uid(n)),
		"data_origin": ORIGIN,
		"last_modified_ms": ms(2026, 10, 2),
		"recording_method": "automatically_recorded",
		"device": device_wire(),
		"start_ms": start,
		"start_offset_s": 7_200,
		"end_ms": start + 60_000,
		"end_offset_s": 7_200,
		"count": 42,
		**overrides,
	}


def resting_heart_rate_wire(n: int, **overrides: Any) -> dict[str, Any]:
	return {
		"hc_id": str(uid(10_000 + n)),
		"data_origin": "com.fitbit.FitbitMobile",
		"last_modified_ms": ms(2026, 10, 2),
		"recording_method": "unknown",
		"device": None,
		"time_ms": ms(2026, 10, 1, 6) + n * HOUR,
		"offset_s": 7_200,
		"beats_per_minute": 54,
		**overrides,
	}


def sleep_wire(n: int, **overrides: Any) -> dict[str, Any]:
	start = ms(2026, 9, 30, 21) + n * 24 * HOUR
	steps = {key: value for key, value in steps_wire(0).items() if key != "count"}
	return {
		**steps,
		"hc_id": str(uid(20_000 + n)),
		"start_ms": start,
		"end_ms": start + 8 * HOUR,
		"title": None,
		"notes": "",
		"stages": [
			{"start_ms": start + HOUR, "end_ms": start + 2 * HOUR, "stage": "deep"},
			{"start_ms": start, "end_ms": start + HOUR, "stage": "light"},
		],
		**overrides,
	}


def window_wire(start: int, hours: int, **overrides: Any) -> dict[str, Any]:
	return {
		"metric": "steps_count_total",
		"start_ms": start,
		"end_ms": start + hours * HOUR,
		"computed_at_ms": ms(2026, 10, 2),
		"buckets": [{"start_ms": start, "value": 321, "data_origins": [ORIGIN]}],
		**overrides,
	}
