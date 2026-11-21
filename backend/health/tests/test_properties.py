"""Convergence: any order or duplication of batches, deletions interleaved, gives the same rows.

Generators draw from tiny pools (four ids, last_modified 0..5, three hours) so that one id
with several versions, equal timestamps with different content, deletions landing exactly on
a version's timestamp, and deletions before inserts are the common case. Owner A gets the
batches in drawn order, owner B a reshuffle with duplicates; B must equal A, and both must
match a reference computed from the union of events, without the code under test.
"""

from typing import Any

import pytest
from django.db import transaction
from hypothesis import event, given, settings
from hypothesis import strategies as st

from health.ingest import AggregateBucket, AggregateWindow, Deletion, IngestBatch, RecordVersion, Source, apply_batch
from health.models import AggregateMetric, RecordType
from health.tests.support import HOUR, ORIGIN, owner, store, uid

IDS = [uid(n) for n in range(1, 5)]
SOURCES = [
	Source(ORIGIN, "automatically_recorded", None, None, None),
	Source(ORIGIN, "manual_entry", "phone", "Google", None),
]
_times = st.integers(0, 5)
_offsets = st.sampled_from([None, 3_600, 7_200])


class _RollbackError(Exception):
	pass


@st.composite
def _record(draw: st.DrawFn) -> RecordVersion:
	record_type = draw(st.sampled_from(list(RecordType)))
	start = draw(st.sampled_from([0, 60_000]))
	end: int | None = None if record_type is RecordType.RESTING_HEART_RATE else start + HOUR
	if record_type is RecordType.STEPS:
		payload: dict[str, Any] = {"count": draw(st.integers(1, 2))}
	elif record_type is RecordType.SLEEP_SESSION:
		stages = sorted(draw(st.lists(st.sampled_from(["light", "deep"]), max_size=2)))
		payload = {"title": draw(st.sampled_from([None, "nap"])), "notes": None, "stages": stages}
	else:
		payload = {"beats_per_minute": draw(st.integers(50, 51))}
	return RecordVersion(
		hc_id=draw(st.sampled_from(IDS)),
		record_type=record_type,
		source=draw(st.sampled_from(SOURCES)),
		start_ms=start,
		start_offset_s=draw(_offsets),
		end_ms=end,
		end_offset_s=None if end is None else draw(_offsets),
		last_modified_ms=draw(_times),
		payload=payload,
	)


@st.composite
def _window(draw: st.DrawFn) -> AggregateWindow:
	start = draw(st.integers(0, 2)) * HOUR
	hours = draw(st.integers(1, 3))
	origins = st.sets(st.sampled_from([ORIGIN, "com.fitbit.FitbitMobile"])).map(lambda found: tuple(sorted(found)))
	buckets = tuple(
		AggregateBucket(start + offset * HOUR, draw(st.integers(0, 2)), draw(origins))
		for offset in sorted(draw(st.sets(st.integers(0, hours - 1))))
	)
	metric = draw(st.sampled_from(list(AggregateMetric)))
	return AggregateWindow(metric, start, start + hours * HOUR, draw(st.integers(0, 3)), buckets)


_batches = st.builds(
	IngestBatch,
	coverage_start_ms=st.sampled_from([None, 0, HOUR, 2 * HOUR + 1]),
	records=st.lists(_record(), max_size=4).map(tuple),
	deletions=st.lists(st.builds(Deletion, hc_id=st.sampled_from(IDS), observed_at_ms=_times), max_size=3).map(tuple),
	aggregate_windows=st.lists(_window(), max_size=2).map(tuple),
)


def _expected_records(batches: list[IngestBatch]) -> tuple[dict[Any, list[tuple[Any, ...]]], dict[Any, int]]:
	"""Per id, the versions that may be stored (absent: none), and the tombstones."""
	tombstones: dict[Any, int] = {}
	for deletion in (deletion for batch in batches for deletion in batch.deletions):
		tombstones[deletion.hc_id] = max(tombstones.get(deletion.hc_id, -1), deletion.observed_at_ms)
	versions: dict[Any, list[RecordVersion]] = {}
	for record in (record for batch in batches for record in batch.records):
		versions.setdefault(record.hc_id, []).append(record)
	allowed = {}
	for hc_id, candidates in versions.items():
		newest = max(candidate.last_modified_ms for candidate in candidates)
		if hc_id not in tombstones or newest > tombstones[hc_id]:
			allowed[hc_id] = [_row(candidate) for candidate in candidates if candidate.last_modified_ms == newest]
	return allowed, tombstones


def _row(version: RecordVersion) -> tuple[Any, ...]:
	return (
		str(version.record_type),
		version.source.key(),
		version.start_ms,
		version.start_offset_s,
		version.end_ms,
		version.end_offset_s,
		version.last_modified_ms,
		version.payload,
	)


def _expected_aggregates(batches: list[IngestBatch]) -> dict[tuple[str, int], list[tuple[int | None, int]]]:
	"""Per metric and hour, every (value, computed_at) a window answered; silence counts only from coverage on."""
	answers: dict[tuple[str, int], list[tuple[int | None, int]]] = {}
	for batch in batches:
		for window in batch.aggregate_windows:
			values = {bucket.start_ms: bucket.value for bucket in window.buckets}
			for hour in range(window.start_ms, window.end_ms, HOUR):
				if hour in values or batch.coverage_start_ms is None or hour >= batch.coverage_start_ms:
					answers.setdefault((window.metric, hour), []).append((values.get(hour), window.computed_at_ms))
	return answers


@pytest.mark.property
@pytest.mark.django_db
@given(batches=st.lists(_batches, min_size=1, max_size=5), data=st.data())
@settings(max_examples=200, deadline=None)
def test_any_order_and_duplication_converges(batches: list[IngestBatch], data: st.DataObject):
	extras = data.draw(st.lists(st.sampled_from(batches), max_size=len(batches)), label="duplicates")
	reshuffled = data.draw(st.permutations([*batches, *extras]), label="order")
	seen: dict[Any, set[int]] = {}
	for record in (record for batch in batches for record in batch.records):
		seen.setdefault(record.hc_id, set()).add(record.last_modified_ms)
	if any(len(times) > 1 for times in seen.values()):
		event("one id, several last_modified")
	deleted_before = {deletion.hc_id for batch in reshuffled[:-1] for deletion in batch.deletions}
	if deleted_before & {record.hc_id for record in reshuffled[-1].records}:
		event("deletion arrives before an insert")

	# Each example rolls back its own rows, since pytest-django's transaction spans all examples.
	with pytest.raises(_RollbackError), transaction.atomic():
		owner_a, owner_b = owner(), owner()
		for batch in batches:
			apply_batch(owner_a, batch)
		for batch in reshuffled:
			apply_batch(owner_b, batch)

		final = store(owner_a)
		assert store(owner_b) == final

		allowed, tombstones = _expected_records(batches)
		assert final["tombstones"] == tombstones
		assert set(final["records"]) == set(allowed)
		for hc_id, row in final["records"].items():
			assert row in allowed[hc_id]

		answers = _expected_aggregates(batches)
		assert set(final["aggregates"]) == set(answers)
		for key, (value, _origins, computed_at) in final["aggregates"].items():
			newest = max(at for _, at in answers[key])
			present = [answer for answer, at in answers[key] if at == newest and answer is not None]
			assert (computed_at, value) == (newest, max(present) if present else None)
		raise _RollbackError
