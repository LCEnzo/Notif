"""Export profiles: a profile chooses rows, a writer formats them. One file per record type.

``raw`` is every stored record, with sleep stages unnested to one row each. ``daily``
rolls up per local day in the export time zone: steps and sleep from HC's hourly
aggregates, resting heart rate as the day's latest record. Sleep is counted per
noon-to-noon night, labelled with the date it ends on (the wake-up date).
docs/architecture/health-ingest.md defines every column.
"""

import csv
from collections.abc import Callable, Iterable, Iterator
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from enum import StrEnum
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

from health.ingest import Source
from health.models import (
	HOUR_MS,
	AggregateMetric,
	HealthAggregate,
	HealthIngestBatch,
	HealthRecord,
	HealthSource,
	RecordType,
)

_EPOCH = datetime(1970, 1, 1, tzinfo=UTC)
_DAY_MS = 24 * HOUR_MS
# Rows fetched per round trip while streaming; memory stays bounded by this, not by the export's size.
_FETCH = 2_000
_NOON = time(12)

type _Label = Callable[[int, ZoneInfo], date]
type _Window = Callable[[date, ZoneInfo], tuple[int, int]]


class Profile(StrEnum):
	RAW = "raw"
	DAILY = "daily"


class Format(StrEnum):
	CSV = "csv"


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
	format: Format = Format.CSV


@dataclass(frozen=True, slots=True)
class ExportedFile:
	record_type: RecordType
	path: Path
	rows: int


def export(spec: ExportSpec) -> list[ExportedFile]:
	if spec.start is not None and spec.end is not None and spec.start > spec.end:
		raise ValueError(f"start {spec.start} is after end {spec.end}.")
	spec.output_dir.mkdir(parents=True, exist_ok=True)
	exported = []
	for record_type in spec.types:
		header, rows = _PROFILES[spec.profile](spec, record_type)
		path = spec.output_dir / f"{spec.profile}-{record_type}.{spec.format}"
		exported.append(ExportedFile(record_type, path, _write_csv(path, header, rows)))
	return exported


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
	if isinstance(value, bool):
		return "true" if value else "false"
	return value


# ── time ─────────────────────────────────────────────────────


def _instant(epoch_ms: int) -> datetime:
	# Integer arithmetic: fromtimestamp() goes through a float and can be off by a millisecond.
	return _EPOCH + timedelta(milliseconds=epoch_ms)


def _epoch_ms(moment: datetime) -> int:
	return (moment - _EPOCH) // timedelta(milliseconds=1)


def _utc(epoch_ms: int | None) -> str | None:
	if epoch_ms is None:
		return None
	return _instant(epoch_ms).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _local(epoch_ms: int | None, tz: ZoneInfo) -> str | None:
	if epoch_ms is None:
		return None
	return _instant(epoch_ms).astimezone(tz).isoformat(timespec="milliseconds")


def _local_midnight(day: date, tz: ZoneInfo) -> int:
	return _epoch_ms(datetime.combine(day, time(0), tzinfo=tz))


def _day_of(epoch_ms: int, tz: ZoneInfo) -> date:
	return _instant(epoch_ms).astimezone(tz).date()


def _night_of(epoch_ms: int, tz: ZoneInfo) -> date:
	"""The wake-up date of the noon-to-noon night containing the instant."""
	local = _instant(epoch_ms).astimezone(tz)
	return local.date() + timedelta(days=1) if local.time() >= _NOON else local.date()


def _day_window(day: date, tz: ZoneInfo) -> tuple[int, int]:
	return _local_midnight(day, tz), _local_midnight(day + timedelta(days=1), tz)


def _night_window(day: date, tz: ZoneInfo) -> tuple[int, int]:
	return (
		_epoch_ms(datetime.combine(day - timedelta(days=1), _NOON, tzinfo=tz)),
		_epoch_ms(datetime.combine(day, _NOON, tzinfo=tz)),
	)


def _hours_in(start_ms: int, end_ms: int) -> int:
	"""How many UTC-hour buckets start inside ``[start_ms, end_ms)``."""
	first = -(-start_ms // HOUR_MS) * HOUR_MS
	return max(0, -(-(end_ms - first) // HOUR_MS))


def _bounds(spec: ExportSpec, window: _Window) -> dict[str, int]:
	"""A query range covering every window in the export, padded a day; exact filtering is by label."""
	bounds: dict[str, int] = {}
	if spec.start is not None:
		bounds["gte"] = window(spec.start, spec.tz)[0] - _DAY_MS
	if spec.end is not None:
		bounds["lt"] = window(spec.end, spec.tz)[1] + _DAY_MS
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
	sources = {row.pk: Source.from_row(row) for row in HealthSource.objects.all()}
	bounds = {f"start_ms__{op}": value for op, value in _bounds(spec, _day_window).items()}
	records = (
		HealthRecord.objects.filter(owner_id=spec.owner_id, record_type=record_type, **bounds)
		.order_by("start_ms", "hc_id")
		.iterator(chunk_size=_FETCH)
	)
	for record in records:
		if not _in_range(spec, _day_of(record.start_ms, spec.tz)):
			continue
		source = sources[record.source_id]
		common = [
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
		if record_type is RecordType.STEPS:
			yield [*common, payload["count"]]
		elif record_type is RecordType.RESTING_HEART_RATE:
			yield [*common, payload["beats_per_minute"]]
		else:
			session = [*common, payload["title"], payload["notes"]]
			stages = payload["stages"]
			if not stages:
				yield [*session, None, None, None, None, None]
			for stage in stages:
				yield [
					*session,
					stage["stage"],
					_utc(stage["start_ms"]),
					_local(stage["start_ms"], spec.tz),
					_utc(stage["end_ms"]),
					_local(stage["end_ms"], spec.tz),
				]


# ── daily ────────────────────────────────────────────────────

_DAILY_HEADER = ["date", "type", "value", "unit", "window_start_utc", "window_end_utc", "n", "partial"]


@dataclass(slots=True)
class _Group:
	label: date
	total: int = 0
	with_value: int = 0
	observed: int = 0
	latest: tuple[int, int, str] | None = None
	latest_value: int | None = None


def _daily(spec: ExportSpec, record_type: RecordType) -> tuple[list[str], Iterator[list[Any]]]:
	if record_type is RecordType.RESTING_HEART_RATE:
		return _DAILY_HEADER, _daily_latest(spec, record_type)
	return _DAILY_HEADER, _daily_from_aggregates(spec, record_type)


_AGGREGATED: dict[RecordType, tuple[AggregateMetric, str, _Label, _Window]] = {
	RecordType.STEPS: (AggregateMetric.STEPS_COUNT_TOTAL, "count", _day_of, _day_window),
	RecordType.SLEEP_SESSION: (AggregateMetric.SLEEP_DURATION_TOTAL, "s", _night_of, _night_window),
}


def _daily_from_aggregates(spec: ExportSpec, record_type: RecordType) -> Iterator[list[Any]]:
	"""Sum HC's hourly answers per window. A window with an hour HC was never asked about is partial."""
	metric, unit, label_of, window_of = _AGGREGATED[record_type]
	bounds = {f"bucket_start_ms__{op}": value for op, value in _bounds(spec, window_of).items()}
	rows = (
		HealthAggregate.objects.filter(owner_id=spec.owner_id, metric=metric, **bounds)
		.order_by("bucket_start_ms")
		.values_list("bucket_start_ms", "value")
		.iterator(chunk_size=_FETCH)
	)

	def emit(group: _Group) -> list[Any]:
		start_ms, end_ms = window_of(group.label, spec.tz)
		value = _seconds(group.total) if metric is AggregateMetric.SLEEP_DURATION_TOTAL else group.total
		partial = group.observed < _hours_in(start_ms, end_ms)
		return [group.label, record_type, value, unit, _utc(start_ms), _utc(end_ms), group.with_value, partial]

	group: _Group | None = None
	for bucket_start_ms, value in rows:
		label = label_of(bucket_start_ms, spec.tz)
		if not _in_range(spec, label):
			continue
		if group is None or group.label != label:
			if group is not None:
				yield emit(group)
			group = _Group(label)
		group.observed += 1
		if value is not None:
			group.total += value
			group.with_value += 1
	if group is not None:
		yield emit(group)


def _daily_latest(spec: ExportSpec, record_type: RecordType) -> Iterator[list[Any]]:
	"""The day's latest record. Partial when the day starts before what HC let the phone read."""
	floor = _coverage_floor(spec.owner_id)
	bounds = {f"start_ms__{op}": value for op, value in _bounds(spec, _day_window).items()}
	rows = (
		HealthRecord.objects.filter(owner_id=spec.owner_id, record_type=record_type, **bounds)
		.order_by("start_ms", "hc_id")
		.values_list("start_ms", "last_modified_ms", "hc_id", "payload")
		.iterator(chunk_size=_FETCH)
	)

	def emit(group: _Group) -> list[Any]:
		start_ms, end_ms = _day_window(group.label, spec.tz)
		partial = floor is not None and start_ms < floor
		return [group.label, record_type, group.latest_value, "bpm", _utc(start_ms), _utc(end_ms), group.total, partial]

	group: _Group | None = None
	for start_ms, last_modified_ms, hc_id, payload in rows:
		label = _day_of(start_ms, spec.tz)
		if not _in_range(spec, label):
			continue
		if group is None or group.label != label:
			if group is not None:
				yield emit(group)
			group = _Group(label)
		group.total += 1
		rank = (start_ms, last_modified_ms, str(hc_id))
		if group.latest is None or rank > group.latest:
			group.latest = rank
			group.latest_value = payload["beats_per_minute"]
	if group is not None:
		yield emit(group)


def _coverage_floor(owner_id: int) -> int | None:
	"""The earliest instant any batch could read; None when one had the history permission, or none exist."""
	batches = HealthIngestBatch.objects.filter(owner_id=owner_id)
	if batches.filter(coverage_start_ms__isnull=True).exists():
		return None
	floors = batches.values_list("coverage_start_ms", flat=True).order_by("coverage_start_ms")[:1]
	return next(iter(floors), None)


def _seconds(milliseconds: int) -> str:
	"""Milliseconds as exact decimal seconds: 1500 -> "1.5"."""
	whole, fraction = divmod(milliseconds, 1000)
	return str(whole) if not fraction else f"{whole}.{fraction:03d}".rstrip("0")


_PROFILES = {Profile.RAW: _raw, Profile.DAILY: _daily}
