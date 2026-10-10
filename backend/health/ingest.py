"""Applying one ingest batch to the store.

Per owner and HC id, the state is the newest version seen plus the newest deletion seen; the
record exists iff that version was modified after that deletion. Per owner, metric and hour,
it is the newest aggregate answer seen. Both are maxima over total orders, so applying the
same batches in any order, any number of times, gives the same rows.

Callers bound the batch (the endpoint caps it at ``limits.MAX_INGEST_ITEMS``), which keeps
every ``IN (...)`` lookup far below SQLite's variable limit.
"""

from __future__ import annotations

import json
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from typing import Any
from uuid import UUID

from django.db import transaction

from health.models import (
	AggregateMetric,
	HealthAggregate,
	HealthDeletion,
	HealthIngestBatch,
	HealthRecord,
	HealthSource,
	RecordType,
)

HOUR_MS = 3_600_000

type SourceKey = tuple[str, str, str, str, str]


@dataclass(frozen=True, slots=True)
class Source:
	"""Who wrote a record. ``device_type`` is None when HC reported no device."""

	data_origin: str
	recording_method: str
	device_type: str | None
	device_manufacturer: str | None
	device_model: str | None

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
	def of(cls, row: HealthSource) -> Source:
		nulls = (row.device_type or None, row.device_manufacturer or None, row.device_model or None)
		return cls(row.data_origin, row.recording_method, *nulls)


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
		"""Newer ``last_modified_ms`` wins; equal ones are ordered by content, so every order picks the same."""
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
	def of(cls, row: HealthRecord) -> RecordVersion:
		return cls(
			hc_id=row.hc_id,
			record_type=RecordType(row.record_type),
			source=Source.of(row.source),
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
	records_deleted: int
	aggregates_written: int


@dataclass(frozen=True, slots=True, order=True)
class _Answer:
	"""HC's answer for one metric and hour. Field order is the rank: newest, then a value over none, then larger."""

	computed_at_ms: int
	has_value: bool
	value: int
	data_origins: tuple[str, ...]


def apply_batch(owner_id: int, batch: IngestBatch) -> IngestOutcome:
	"""Apply ``batch`` atomically for ``owner_id`` and log it."""
	with transaction.atomic():
		records_written, records_deleted = _apply_records(owner_id, batch.records, batch.deletions)
		aggregates_written = _apply_aggregates(owner_id, batch.aggregate_windows, batch.coverage_start_ms)
		logged = HealthIngestBatch.objects.create(
			owner_id=owner_id,
			coverage_start_ms=batch.coverage_start_ms,
			record_count=len(batch.records),
			deletion_count=len(batch.deletions),
			aggregate_hour_count=sum(window.hours for window in batch.aggregate_windows),
		)
	return IngestOutcome(logged.pk, records_written, records_deleted, aggregates_written)


def _apply_records(owner_id: int, records: Sequence[RecordVersion], deletions: Sequence[Deletion]) -> tuple[int, int]:
	incoming: dict[UUID, RecordVersion] = {}
	for record in records:
		if record.hc_id not in incoming or record.rank() > incoming[record.hc_id].rank():
			incoming[record.hc_id] = record
	requested: dict[UUID, int] = {}
	for deletion in deletions:
		requested[deletion.hc_id] = max(requested.get(deletion.hc_id, deletion.observed_at_ms), deletion.observed_at_ms)

	ids = incoming.keys() | requested.keys()
	stored = {
		row.hc_id: RecordVersion.of(row)
		for row in HealthRecord.objects.filter(owner_id=owner_id, hc_id__in=ids).select_related("source")
	}
	floors = dict(
		HealthDeletion.objects.filter(owner_id=owner_id, hc_id__in=ids).values_list("hc_id", "observed_at_ms")
	)

	to_write: list[RecordVersion] = []
	to_delete: list[UUID] = []
	tombstones: list[HealthDeletion] = []
	for hc_id in ids:
		floor = floors.get(hc_id)
		if hc_id in requested and (floor is None or requested[hc_id] > floor):
			floor = requested[hc_id]
			tombstones.append(HealthDeletion(owner_id=owner_id, hc_id=hc_id, observed_at_ms=floor))
		current, candidate = stored.get(hc_id), incoming.get(hc_id)
		# max() keeps the first of equals, so a replayed version is not rewritten.
		newest = max(filter(None, (current, candidate)), key=RecordVersion.rank, default=None)
		alive = newest is not None and (floor is None or newest.last_modified_ms > floor)
		if alive and candidate is not None and newest is candidate:
			to_write.append(candidate)
		elif not alive and current is not None:
			to_delete.append(hc_id)

	_write_records(owner_id, to_write)
	HealthRecord.objects.filter(owner_id=owner_id, hc_id__in=to_delete).delete()
	HealthDeletion.objects.bulk_create(
		tombstones, update_conflicts=True, unique_fields=["owner", "hc_id"], update_fields=["observed_at_ms"]
	)
	return len(to_write), len(to_delete)


def _write_records(owner_id: int, versions: Sequence[RecordVersion]) -> None:
	source_ids = _source_ids(version.source for version in versions)
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
		unique_fields=["owner", "hc_id"],
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
	)


def _source_ids(sources: Iterable[Source]) -> dict[SourceKey, int]:
	# A batch carries a handful of distinct sources, so one lookup each is cheap.
	ids: dict[SourceKey, int] = {}
	for key in {source.key() for source in sources}:
		origin, method, device_type, manufacturer, model = key
		row, _ = HealthSource.objects.get_or_create(
			data_origin=origin,
			recording_method=method,
			device_type=device_type,
			device_manufacturer=manufacturer,
			device_model=model,
		)
		ids[key] = row.pk
	return ids


def _apply_aggregates(owner_id: int, windows: Iterable[AggregateWindow], coverage_start_ms: int | None) -> int:
	answers: dict[tuple[str, int], _Answer] = {}
	for window in windows:
		buckets = {bucket.start_ms: bucket for bucket in window.buckets}
		for hour in range(window.start_ms, window.end_ms, HOUR_MS):
			bucket = buckets.get(hour)
			if bucket is None and coverage_start_ms is not None and hour < coverage_start_ms:
				continue  # Before coverage, HC hid the data: silence there means nothing.
			answer = _Answer(
				window.computed_at_ms,
				has_value=bucket is not None,
				value=bucket.value if bucket else 0,
				data_origins=bucket.data_origins if bucket else (),
			)
			key = (str(window.metric), hour)
			if key not in answers or answer > answers[key]:
				answers[key] = answer

	stored = {
		(row.metric, row.bucket_start_ms): _Answer(
			row.computed_at_ms, row.value is not None, row.value or 0, tuple(row.data_origins)
		)
		for row in HealthAggregate.objects.filter(owner_id=owner_id, bucket_start_ms__in={hour for _, hour in answers})
	}
	to_write = [
		HealthAggregate(
			owner_id=owner_id,
			metric=metric,
			bucket_start_ms=hour,
			value=answer.value if answer.has_value else None,
			data_origins=list(answer.data_origins),
			computed_at_ms=answer.computed_at_ms,
		)
		for (metric, hour), answer in answers.items()
		if (metric, hour) not in stored or answer > stored[(metric, hour)]
	]
	HealthAggregate.objects.bulk_create(
		to_write,
		update_conflicts=True,
		unique_fields=["owner", "metric", "bucket_start_ms"],
		update_fields=["value", "data_origins", "computed_at_ms"],
	)
	return len(to_write)
