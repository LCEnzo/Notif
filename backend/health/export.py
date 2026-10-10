"""Export profiles as CSV, one long-format file per record type; columns in docs/architecture/health-ingest.md.

``raw`` is every stored record, with sleep stages unnested to a row each. ``daily`` rolls up
per local day in the export time zone: steps and sleep from HC's hourly aggregates, resting
heart rate as the day's latest reading. Sleep counts per noon-to-noon night, labelled with
the date it ends on (the wake-up date).
"""

import csv
from collections.abc import Callable, Iterable, Iterator
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from enum import StrEnum
from itertools import groupby
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

from django.db.models import F

from health.ingest import HOUR_MS, Source
from health.models import AggregateMetric, HealthAggregate, HealthIngestBatch, HealthRecord, HealthSource, RecordType

_EPOCH = datetime(1970, 1, 1, tzinfo=UTC)
_DAY_MS = 24 * HOUR_MS
# Rows per round trip while streaming: memory is bounded by this, not by the export's size.
_FETCH = 2_000
_NOON = time(12)

type _Label = Callable[[int, ZoneInfo], date]
type _Window = Callable[[date, ZoneInfo], tuple[int, int]]


class Profile(StrEnum):
	RAW = "raw"
	DAILY = "daily"


@dataclass(frozen=True, slots=True)
class ExportSpec:
	owner_id: int
	profile: Profile
	types: tuple[RecordType, ...]
	tz: ZoneInfo
	output_dir: Path
	# Local dates in ``tz``, both inclusive; None leaves that side open.
	start: date | None = None
	end: date | None = None


def export(spec: ExportSpec) -> list[tuple[Path, int]]:
	"""Write one file per type; returns each path with its row count."""
	if spec.start is not None and spec.end is not None and spec.start > spec.end:
		raise ValueError(f"start {spec.start} is after end {spec.end}.")
	spec.output_dir.mkdir(parents=True, exist_ok=True)
	written = []
	for record_type in spec.types:
		header, rows = (_raw if spec.profile is Profile.RAW else _daily)(spec, record_type)
		path = spec.output_dir / f"{spec.profile}-{record_type}.csv"
		written.append((path, _write_csv(path, header, rows)))
	return written


def _write_csv(path: Path, header: list[str], rows: Iterable[list[Any]]) -> int:
	"""Write through a temporary file, so an interrupted export never leaves a truncated CSV."""
	partial = path.with_name(f"{path.name}.partial")
	count = 0
	with partial.open("w", encoding="utf-8", newline="") as handle:
		writer = csv.writer(handle, lineterminator="\n")
		writer.writerow(header)
		for row in rows:
			writer.writerow([_cell(value) for value in row])
			count += 1
	partial.replace(path)
	return count


def _cell(value: Any) -> Any:
	if value is None:
		return ""
	return ("true" if value else "false") if isinstance(value, bool) else value


# ── time ─────────────────────────────────────────────────────


def _instant(epoch_ms: int) -> datetime:
	# Integer arithmetic: fromtimestamp() goes through a float and can be off by a millisecond.
	return _EPOCH + timedelta(milliseconds=epoch_ms)


def _epoch_ms(moment: datetime) -> int:
	return (moment - _EPOCH) // timedelta(milliseconds=1)


def _utc(epoch_ms: int | None) -> str | None:
	return None if epoch_ms is None else _instant(epoch_ms).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _local(epoch_ms: int | None, tz: ZoneInfo) -> str | None:
	return None if epoch_ms is None else _instant(epoch_ms).astimezone(tz).isoformat(timespec="milliseconds")


def _day_of(epoch_ms: int, tz: ZoneInfo) -> date:
	return _instant(epoch_ms).astimezone(tz).date()


def _night_of(epoch_ms: int, tz: ZoneInfo) -> date:
	"""The wake-up date of the noon-to-noon night containing the instant."""
	local = _instant(epoch_ms).astimezone(tz)
	return local.date() + timedelta(days=1) if local.time() >= _NOON else local.date()


def _day_window(day: date, tz: ZoneInfo) -> tuple[int, int]:
	return _epoch_ms(datetime.combine(day, time(0), tzinfo=tz)), _epoch_ms(
		datetime.combine(day + timedelta(days=1), time(0), tzinfo=tz)
	)


def _night_window(day: date, tz: ZoneInfo) -> tuple[int, int]:
	return _epoch_ms(datetime.combine(day - timedelta(days=1), _NOON, tzinfo=tz)), _epoch_ms(
		datetime.combine(day, _NOON, tzinfo=tz)
	)


def _hours_in(start_ms: int, end_ms: int) -> int:
	"""How many UTC-hour buckets start inside ``[start_ms, end_ms)``."""
	first = -(-start_ms // HOUR_MS) * HOUR_MS
	return max(0, -(-(end_ms - first) // HOUR_MS))


def _bounds(spec: ExportSpec, field: str, window: _Window) -> dict[str, int]:
	"""A query range covering every window in the export, padded a day; exact filtering is by label."""
	bounds = {}
	if spec.start is not None:
		bounds[f"{field}__gte"] = window(spec.start, spec.tz)[0] - _DAY_MS
	if spec.end is not None:
		bounds[f"{field}__lt"] = window(spec.end, spec.tz)[1] + _DAY_MS
	return bounds


def _in_range(spec: ExportSpec, label: date) -> bool:
	return (spec.start is None or label >= spec.start) and (spec.end is None or label <= spec.end)


# ── raw ──────────────────────────────────────────────────────

_RAW_COMMON = [
	"hc_id",
	"data_origin",
	"recording_method",
	"device_type",
	"device_manufacturer",
	"device_model",
	"start_utc",
	"start_local",
	"start_offset_s",
	"end_utc",
	"end_local",
	"end_offset_s",
	"last_modified_utc",
]
_RAW_EXTRA: dict[RecordType, list[str]] = {
	RecordType.STEPS: ["count"],
	RecordType.RESTING_HEART_RATE: ["beats_per_minute"],
	RecordType.SLEEP_SESSION: [
		"title",
		"notes",
		"stage",
		"stage_start_utc",
		"stage_start_local",
		"stage_end_utc",
		"stage_end_local",
	],
}


def _raw(spec: ExportSpec, record_type: RecordType) -> tuple[list[str], Iterator[list[Any]]]:
	return [*_RAW_COMMON, *_RAW_EXTRA[record_type]], _raw_rows(spec, record_type)


def _raw_rows(spec: ExportSpec, record_type: RecordType) -> Iterator[list[Any]]:
	sources = {row.pk: Source.of(row) for row in HealthSource.objects.all()}
	records = (
		HealthRecord.objects.filter(
			owner_id=spec.owner_id, record_type=record_type, **_bounds(spec, "start_ms", _day_window)
		)
		.order_by("start_ms", "hc_id")
		.iterator(chunk_size=_FETCH)
	)
	for record in records:
		if not _in_range(spec, _day_of(record.start_ms, spec.tz)):
			continue
		source = sources[record.source_id]
		row = [
			str(record.hc_id),
			source.data_origin,
			source.recording_method,
			source.device_type,
			source.device_manufacturer,
			source.device_model,
			_utc(record.start_ms),
			_local(record.start_ms, spec.tz),
			record.start_offset_s,
			_utc(record.end_ms),
			_local(record.end_ms, spec.tz),
			record.end_offset_s,
			_utc(record.last_modified_ms),
		]
		payload: dict[str, Any] = record.payload
		if record_type is not RecordType.SLEEP_SESSION:
			yield [*row, payload[_RAW_EXTRA[record_type][0]]]
			continue
		row += [payload["title"], payload["notes"]]
		if not payload["stages"]:
			yield [*row, None, None, None, None, None]
		for stage in payload["stages"]:
			start, end = stage["start_ms"], stage["end_ms"]
			yield [*row, stage["stage"], _utc(start), _local(start, spec.tz), _utc(end), _local(end, spec.tz)]


# ── daily ────────────────────────────────────────────────────

_DAILY_HEADER = ["date", "type", "value", "unit", "window_start_utc", "window_end_utc", "n", "partial"]
_AGGREGATED: dict[RecordType, tuple[AggregateMetric, str, _Label, _Window]] = {
	RecordType.STEPS: (AggregateMetric.STEPS_COUNT_TOTAL, "count", _day_of, _day_window),
	RecordType.SLEEP_SESSION: (AggregateMetric.SLEEP_DURATION_TOTAL, "s", _night_of, _night_window),
}


def _daily(spec: ExportSpec, record_type: RecordType) -> tuple[list[str], Iterator[list[Any]]]:
	rows = _daily_latest(spec) if record_type is RecordType.RESTING_HEART_RATE else _daily_sum(spec, record_type)
	return _DAILY_HEADER, rows


def _daily_sum(spec: ExportSpec, record_type: RecordType) -> Iterator[list[Any]]:
	"""Sum HC's hourly answers per window; a window with an hour HC was never asked about is partial."""
	metric, unit, label_of, window_of = _AGGREGATED[record_type]
	answers = (
		HealthAggregate.objects.filter(
			owner_id=spec.owner_id, metric=metric, **_bounds(spec, "bucket_start_ms", window_of)
		)
		.order_by("bucket_start_ms")
		.values_list("bucket_start_ms", "value")
		.iterator(chunk_size=_FETCH)
	)
	for label, group in groupby(answers, key=lambda answer: label_of(answer[0], spec.tz)):
		if not _in_range(spec, label):
			continue
		values = [value for _, value in group]
		present = [value for value in values if value is not None]
		start_ms, end_ms = window_of(label, spec.tz)
		total = _seconds(sum(present)) if unit == "s" else sum(present)
		partial = len(values) < _hours_in(start_ms, end_ms)
		yield [label, record_type, total, unit, _utc(start_ms), _utc(end_ms), len(present), partial]


def _daily_latest(spec: ExportSpec) -> Iterator[list[Any]]:
	"""The day's latest resting heart rate. Partial when the day starts before what HC let the phone read."""
	floor = _coverage_floor(spec.owner_id)
	readings = (
		HealthRecord.objects.filter(
			owner_id=spec.owner_id,
			record_type=RecordType.RESTING_HEART_RATE,
			**_bounds(spec, "start_ms", _day_window),
		)
		.order_by("start_ms", "hc_id")
		.values_list("start_ms", "last_modified_ms", "hc_id", "payload")
		.iterator(chunk_size=_FETCH)
	)
	for label, group in groupby(readings, key=lambda reading: _day_of(reading[0], spec.tz)):
		if not _in_range(spec, label):
			continue
		day = list(group)
		# Ties on time go to the newer modification, then the larger id.
		latest = max(day, key=lambda reading: (reading[0], reading[1], str(reading[2])))
		start_ms, end_ms = _day_window(label, spec.tz)
		partial = floor is not None and start_ms < floor
		bpm = latest[3]["beats_per_minute"]
		yield [label, RecordType.RESTING_HEART_RATE, bpm, "bpm", _utc(start_ms), _utc(end_ms), len(day), partial]


def _coverage_floor(owner_id: int) -> int | None:
	"""The earliest instant any batch could read; None when one had the history permission, or none exist."""
	# Null (history granted) sorts first, so one such batch lifts the floor.
	floors = HealthIngestBatch.objects.filter(owner_id=owner_id).values_list("coverage_start_ms", flat=True)
	return floors.order_by(F("coverage_start_ms").asc(nulls_first=True)).first()


def _seconds(milliseconds: int) -> str:
	"""Exact decimal seconds: 1500 -> "1.5"."""
	whole, fraction = divmod(milliseconds, 1000)
	return str(whole) if not fraction else f"{whole}.{fraction:03d}".rstrip("0")
