"""Applying one ingest batch to the store.

Per owner and HC id, the state is the newest version seen plus the newest deletion
seen; the record exists iff that version was modified after that deletion. Per owner,
metric and hour, it is the newest aggregate observation seen. Both are maxima over a
total order, so applying the same events in any order, any number of times, gives
the same rows. docs/architecture/health-ingest.md states the rules for clients.
"""

from __future__ import annotations

import json
from collections.abc import Iterable, Iterator, Mapping, Sequence
from dataclasses import dataclass
from typing import Any
from uuid import UUID

from django.db import router, transaction

from accounts.models import User
from health.models import (
	HOUR_MS,
	AggregateMetric,
	HealthAggregate,
	HealthDeletion,
	HealthIngestBatch,
	HealthRecord,
	HealthSource,
	RecordType,
)

# Rows per IN (...) lookup and per bulk write; well under SQLite's variable limit.
_CHUNK = 500

type SourceKey = tuple[str, str, str, str, str]


@dataclass(frozen=True, slots=True)
class Source:
	"""Who wrote a record. ``device_type`` is None when HC reported no device."""

	data_origin: str
	recording_method: str
	device_type: str | None
	device_manufacturer: str | None
	device_model: str | None

	def __post_init__(self) -> None:
		if self.device_type is None and (self.device_manufacturer is not None or self.device_model is not None):
			raise ValueError("A source without a device cannot name a device manufacturer or model.")

	def key(self) -> SourceKey:
		"""The stored form: HC's nulls become empty strings (see HealthSource)."""
		return (
			self.data_origin,
			self.recording_method,
			self.device_type or "",
			self.device_manufacturer or "",
			self.device_model or "",
		)

	@classmethod
	def from_row(cls, row: HealthSource) -> Source:
		return cls(
			data_origin=row.data_origin,
			recording_method=row.recording_method,
			device_type=row.device_type or None,
			device_manufacturer=row.device_manufacturer or None,
			device_model=row.device_model or None,
		)


@dataclass(frozen=True, slots=True)
class RecordVersion:
	"""One version of one HC record. ``end_ms`` is None for instantaneous types."""

	hc_id: UUID
	record_type: RecordType
	source: Source
	start_ms: int
	start_offset_s: int | None
	end_ms: int | None
	end_offset_s: int | None
	last_modified_ms: int
	payload: Mapping[str, Any]

	def rank(self) -> tuple[int, str]:
		"""Newer ``last_modified_ms`` wins; equal ones are ordered by content, so ties resolve the same way everywhere."""
		content = [
			str(self.record_type),
			self.source.key(),
			self.start_ms,
			self.start_offset_s,
			self.end_ms,
			self.end_offset_s,
			self.payload,
		]
		return (self.last_modified_ms, json.dumps(content, sort_keys=True, separators=(",", ":")))

	@classmethod
	def from_row(cls, row: HealthRecord, source: Source) -> RecordVersion:
		return cls(
			hc_id=row.hc_id,
			record_type=RecordType(row.record_type),
			source=source,
			start_ms=row.start_ms,
			start_offset_s=row.start_offset_s,
			end_ms=row.end_ms,
			end_offset_s=row.end_offset_s,
			last_modified_ms=row.last_modified_ms,
			payload=row.payload,
		)


@dataclass(frozen=True, slots=True)
class Deletion:
	"""HC reported ``hc_id`` deleted; the client learned of it at ``observed_at_ms``."""

	hc_id: UUID
	observed_at_ms: int


@dataclass(frozen=True, slots=True)
class AggregateBucket:
	start_ms: int
	value: int
	data_origins: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class AggregateWindow:
	"""HC's hourly aggregate over ``[start_ms, end_ms)``. Hours without a bucket had nothing."""

	metric: AggregateMetric
	start_ms: int
	end_ms: int
	computed_at_ms: int
	buckets: tuple[AggregateBucket, ...]

	@property
	def hours(self) -> int:
		return (self.end_ms - self.start_ms) // HOUR_MS


@dataclass(frozen=True, slots=True)
class IngestBatch:
	coverage_start_ms: int | None
	records: tuple[RecordVersion, ...]
	deletions: tuple[Deletion, ...]
	aggregate_windows: tuple[AggregateWindow, ...]

	@property
	def item_count(self) -> int:
		return len(self.records) + len(self.deletions) + sum(window.hours for window in self.aggregate_windows)


@dataclass(frozen=True, slots=True)
class IngestOutcome:
	batch_id: int
	records_written: int
	records_ignored: int
	records_deleted: int
	aggregates_written: int
	aggregates_ignored: int


@dataclass(frozen=True, slots=True)
class _Observation:
	"""What HC answered for one metric and hour. ``value`` None: it had nothing."""

	computed_at_ms: int
	value: int | None
	data_origins: tuple[str, ...]

	def rank(self) -> tuple[int, int, int, tuple[str, ...]]:
		# Ties on computed_at_ms: a value beats nothing, then the larger value, then the origins.
		return (self.computed_at_ms, self.value is not None, self.value or 0, self.data_origins)


@dataclass(frozen=True, slots=True)
class _RecordCounts:
	written: int
	ignored: int
	deleted: int


@dataclass(frozen=True, slots=True)
class _AggregateCounts:
	written: int
	ignored: int


class OwnerGoneError(Exception):
	"""The owner was deleted or deactivated before the batch could be stored."""


def apply_batch_for_live_owner(owner_id: int, batch: IngestBatch) -> IngestOutcome:
	"""``apply_batch``, refused unless ``owner_id`` is an active, undeleted user.

	Checked under the health write lock (transactions are IMMEDIATE). A deletion's purge
	runs after the deletion commits and takes the same lock, so it either waits for this
	batch and removes it, or ran first, and then this check sees the deletion.
	"""
	with transaction.atomic(using=router.db_for_write(HealthRecord)):
		if not User.objects.filter(pk=owner_id, is_active=True).exists():
			raise OwnerGoneError(f"User {owner_id} was deleted or deactivated; the batch was not stored.")
		return apply_batch(owner_id, batch)


def apply_batch(owner_id: int, batch: IngestBatch) -> IngestOutcome:
	"""Apply ``batch`` atomically for ``owner_id`` and log it."""
	with transaction.atomic(using=router.db_for_write(HealthRecord)):
		records = _apply_records(owner_id, batch.records, batch.deletions)
		aggregates = _apply_aggregates(owner_id, batch.aggregate_windows, batch.coverage_start_ms)
		logged = HealthIngestBatch.objects.create(
			owner_id=owner_id,
			coverage_start_ms=batch.coverage_start_ms,
			record_count=len(batch.records),
			deletion_count=len(batch.deletions),
			aggregate_hour_count=sum(window.hours for window in batch.aggregate_windows),
		)
	return IngestOutcome(
		batch_id=logged.pk,
		records_written=records.written,
		records_ignored=records.ignored,
		records_deleted=records.deleted,
		aggregates_written=aggregates.written,
		aggregates_ignored=aggregates.ignored,
	)


def _chunks[T](items: Sequence[T]) -> Iterator[Sequence[T]]:
	for start in range(0, len(items), _CHUNK):
		yield items[start : start + _CHUNK]


def _newest_versions(records: Iterable[RecordVersion]) -> tuple[dict[UUID, RecordVersion], int]:
	"""The winning version per id, and how many lost to another version in the same batch."""
	newest: dict[UUID, RecordVersion] = {}
	losers = 0
	for record in records:
		current = newest.get(record.hc_id)
		if current is not None:
			losers += 1
			if record.rank() <= current.rank():
				continue
		newest[record.hc_id] = record
	return newest, losers


def _apply_records(owner_id: int, records: Sequence[RecordVersion], deletions: Sequence[Deletion]) -> _RecordCounts:
	incoming, ignored = _newest_versions(records)
	deleted_at: dict[UUID, int] = {}
	for deletion in deletions:
		deleted_at[deletion.hc_id] = max(
			deleted_at.get(deletion.hc_id, deletion.observed_at_ms), deletion.observed_at_ms
		)

	ids = sorted(incoming.keys() | deleted_at.keys())
	stored: dict[UUID, HealthRecord] = {}
	tombstones: dict[UUID, int] = {}
	for chunk in _chunks(ids):
		for row in HealthRecord.objects.filter(owner_id=owner_id, hc_id__in=chunk).select_related("source"):
			stored[row.hc_id] = row
		for hc_id, observed_at_ms in HealthDeletion.objects.filter(owner_id=owner_id, hc_id__in=chunk).values_list(
			"hc_id", "observed_at_ms"
		):
			tombstones[hc_id] = observed_at_ms

	to_write: list[RecordVersion] = []
	to_delete: list[UUID] = []
	new_tombstones: list[HealthDeletion] = []
	for hc_id in ids:
		floor = tombstones.get(hc_id)
		requested = deleted_at.get(hc_id)
		if requested is not None and (floor is None or requested > floor):
			floor = requested
			new_tombstones.append(HealthDeletion(owner_id=owner_id, hc_id=hc_id, observed_at_ms=floor))

		stored_row = stored.get(hc_id)
		current = RecordVersion.from_row(stored_row, Source.from_row(stored_row.source)) if stored_row else None
		candidate = incoming.get(hc_id)
		candidate_wins = candidate is not None and (current is None or candidate.rank() > current.rank())
		newest = candidate if candidate_wins else current
		alive = newest is not None and (floor is None or newest.last_modified_ms > floor)

		if candidate is not None:
			if candidate_wins and alive:
				to_write.append(candidate)
			else:
				ignored += 1
		if current is not None and not alive:
			to_delete.append(hc_id)

	_write_records(owner_id, to_write)
	for chunk in _chunks(to_delete):
		HealthRecord.objects.filter(owner_id=owner_id, hc_id__in=chunk).delete()
	HealthDeletion.objects.bulk_create(
		new_tombstones,
		update_conflicts=True,
		unique_fields=["owner_id", "hc_id"],
		update_fields=["observed_at_ms"],
		batch_size=_CHUNK,
	)
	return _RecordCounts(written=len(to_write), ignored=ignored, deleted=len(to_delete))


def _write_records(owner_id: int, versions: Sequence[RecordVersion]) -> None:
	source_ids = _source_ids({version.source for version in versions})
	HealthRecord.objects.bulk_create(
		[
			HealthRecord(
				owner_id=owner_id,
				hc_id=version.hc_id,
				record_type=version.record_type,
				source_id=source_ids[version.source.key()],
				start_ms=version.start_ms,
				start_offset_s=version.start_offset_s,
				end_ms=version.end_ms,
				end_offset_s=version.end_offset_s,
				last_modified_ms=version.last_modified_ms,
				payload=dict(version.payload),
			)
			for version in versions
		],
		update_conflicts=True,
		unique_fields=["owner_id", "hc_id"],
		update_fields=[
			"record_type",
			"source",
			"start_ms",
			"start_offset_s",
			"end_ms",
			"end_offset_s",
			"last_modified_ms",
			"payload",
		],
		batch_size=_CHUNK,
	)


def _source_ids(sources: set[Source]) -> dict[SourceKey, int]:
	keys = sorted({source.key() for source in sources})

	def lookup(wanted: Sequence[SourceKey]) -> dict[SourceKey, int]:
		wanted_keys = set(wanted)
		found: dict[SourceKey, int] = {}
		for chunk in _chunks(sorted({key[0] for key in wanted_keys})):
			for row in HealthSource.objects.filter(data_origin__in=chunk):
				key = (
					row.data_origin,
					row.recording_method,
					row.device_type,
					row.device_manufacturer,
					row.device_model,
				)
				if key in wanted_keys:
					found[key] = row.pk
		return found

	known = lookup(keys)
	missing = [key for key in keys if key not in known]
	if missing:
		HealthSource.objects.bulk_create(
			[
				HealthSource(
					data_origin=origin,
					recording_method=method,
					device_type=device_type,
					device_manufacturer=manufacturer,
					device_model=model,
				)
				for origin, method, device_type, manufacturer, model in missing
			],
			ignore_conflicts=True,
			batch_size=_CHUNK,
		)
		known |= lookup(missing)
	return known


def _observations(
	windows: Iterable[AggregateWindow], coverage_start_ms: int | None
) -> dict[tuple[str, int], _Observation]:
	"""Every hour the windows answered for, newest observation per metric and hour.

	An hour without a bucket counts as an empty answer only from ``coverage_start_ms`` on:
	before it HC hides records, so its silence there means nothing.
	"""
	observed: dict[tuple[str, int], _Observation] = {}

	def offer(key: tuple[str, int], observation: _Observation) -> None:
		current = observed.get(key)
		if current is None or observation.rank() > current.rank():
			observed[key] = observation

	for window in windows:
		answered = {bucket.start_ms: bucket for bucket in window.buckets}
		for hour in range(window.start_ms, window.end_ms, HOUR_MS):
			bucket = answered.get(hour)
			if bucket is not None:
				offer((window.metric, hour), _Observation(window.computed_at_ms, bucket.value, bucket.data_origins))
			elif coverage_start_ms is None or hour >= coverage_start_ms:
				offer((window.metric, hour), _Observation(window.computed_at_ms, None, ()))
	return observed


def _apply_aggregates(
	owner_id: int, windows: Sequence[AggregateWindow], coverage_start_ms: int | None
) -> _AggregateCounts:
	offered = sum(window.hours for window in windows)
	observed = _observations(windows, coverage_start_ms)

	stored: dict[tuple[str, int], _Observation] = {}
	by_metric: dict[str, list[int]] = {}
	for metric, hour in sorted(observed):
		by_metric.setdefault(metric, []).append(hour)
	for metric, hours in by_metric.items():
		for chunk in _chunks(hours):
			for row in HealthAggregate.objects.filter(owner_id=owner_id, metric=metric, bucket_start_ms__in=chunk):
				stored[(row.metric, row.bucket_start_ms)] = _Observation(
					row.computed_at_ms, row.value, tuple(row.data_origins)
				)

	to_write = [
		HealthAggregate(
			owner_id=owner_id,
			metric=metric,
			bucket_start_ms=hour,
			value=observation.value,
			data_origins=list(observation.data_origins),
			computed_at_ms=observation.computed_at_ms,
		)
		for (metric, hour), observation in sorted(observed.items())
		if (current := stored.get((metric, hour))) is None or observation.rank() > current.rank()
	]
	HealthAggregate.objects.bulk_create(
		to_write,
		update_conflicts=True,
		unique_fields=["owner_id", "metric", "bucket_start_ms"],
		update_fields=["value", "data_origins", "computed_at_ms"],
		batch_size=_CHUNK,
	)
	return _AggregateCounts(written=len(to_write), ignored=offered - len(to_write))
