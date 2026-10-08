"""Convergence: any order or duplication of batches, deletions interleaved, gives the same rows.

Generators draw from tiny pools (four ids, last_modified 0..5, three hours) so the same
id with different versions, equal timestamps with different content, deletions before
inserts, and deletions landing exactly on a version's timestamp are the common case.
Owner A gets the batches in drawn order, owner B a reshuffle with duplicates; B must
equal A, and both must match a reference computed directly from the union of events.
"""

from typing import Any

import pytest
from hypothesis import event, given, settings
from hypothesis import strategies as st
from hypothesis.extra.django import TestCase as HypothesisTestCase
from rest_framework.exceptions import ValidationError

from health.ingest import AggregateBucket, AggregateWindow, Deletion, IngestBatch, RecordVersion, Source, apply_batch
from health.limits import MAX_INGEST_ITEMS
from health.models import AggregateMetric, RecordType
from health.serializers import HealthIngestSerializer
from health.tests.support import HEALTH_DATABASES, HOUR, ORIGIN, steps_wire, store, uid

OWNER_A = 1
OWNER_B = 2
IDS = [uid(n) for n in range(1, 5)]
SOURCES = [
	Source(ORIGIN, "automatically_recorded", None, None, None),
	Source(ORIGIN, "manual_entry", "phone", "Google", None),
]
_times = st.integers(min_value=0, max_value=5)
_offsets = st.sampled_from([None, 3_600, 7_200])


@st.composite
def _record(draw: st.DrawFn) -> RecordVersion:
	hc_id = draw(st.sampled_from(IDS))
	record_type = draw(st.sampled_from(list(RecordType)))
	start = draw(st.sampled_from([0, 60_000]))
	common: dict[str, Any] = {
		"hc_id": hc_id,
		"record_type": record_type,
		"source": draw(st.sampled_from(SOURCES)),
		"start_ms": start,
		"start_offset_s": draw(_offsets),
		"last_modified_ms": draw(_times),
	}
	if record_type is RecordType.RESTING_HEART_RATE:
		return RecordVersion(
			**common, end_ms=None, end_offset_s=None, payload={"beats_per_minute": draw(st.integers(50, 51))}
		)
	end = start + HOUR
	if record_type is RecordType.STEPS:
		payload: dict[str, Any] = {"count": draw(st.integers(1, 2))}
	else:
		stages = draw(st.lists(st.sampled_from(["light", "deep"]), max_size=2))
		payload = {
			"title": draw(st.sampled_from([None, "nap"])),
			"notes": None,
			"stages": [{"start_ms": start, "end_ms": end, "stage": stage} for stage in sorted(stages)],
		}
	return RecordVersion(**common, end_ms=end, end_offset_s=draw(_offsets), payload=payload)


@st.composite
def _window(draw: st.DrawFn) -> AggregateWindow:
	start = draw(st.integers(0, 2)) * HOUR
	hours = draw(st.integers(1, 3))
	offsets = draw(st.sets(st.integers(0, hours - 1)))
	return AggregateWindow(
		metric=draw(st.sampled_from(list(AggregateMetric))),
		start_ms=start,
		end_ms=start + hours * HOUR,
		computed_at_ms=draw(st.integers(0, 3)),
		buckets=tuple(
			AggregateBucket(
				start_ms=start + offset * HOUR,
				value=draw(st.integers(0, 2)),
				data_origins=tuple(sorted(draw(st.sets(st.sampled_from([ORIGIN, "com.fitbit.FitbitMobile"]))))),
			)
			for offset in sorted(offsets)
		),
	)


_batches = st.builds(
	IngestBatch,
	coverage_start_ms=st.sampled_from([None, 0, HOUR, 2 * HOUR + 1]),
	records=st.lists(_record(), max_size=4).map(tuple),
	deletions=st.lists(st.builds(Deletion, hc_id=st.sampled_from(IDS), observed_at_ms=_times), max_size=3).map(tuple),
	aggregate_windows=st.lists(_window(), max_size=2).map(tuple),
)


def _expected_records(batches: list[IngestBatch]) -> tuple[dict[Any, list[RecordVersion]], dict[Any, int]]:
	"""Per id: the versions that may be stored (empty: none), and the tombstone. Written from the rule, not the code."""
	tombstones: dict[Any, int] = {}
	for deletion in (deletion for batch in batches for deletion in batch.deletions):
		tombstones[deletion.hc_id] = max(tombstones.get(deletion.hc_id, -1), deletion.observed_at_ms)
	versions: dict[Any, list[RecordVersion]] = {}
	for record in (record for batch in batches for record in batch.records):
		versions.setdefault(record.hc_id, []).append(record)
	allowed: dict[Any, list[RecordVersion]] = {}
	for hc_id, candidates in versions.items():
		newest = max(candidate.last_modified_ms for candidate in candidates)
		if hc_id in tombstones and newest <= tombstones[hc_id]:
			continue
		allowed[hc_id] = [candidate for candidate in candidates if candidate.last_modified_ms == newest]
	return allowed, tombstones


def _expected_aggregates(batches: list[IngestBatch]) -> dict[tuple[str, int], list[tuple[int | None, int]]]:
	"""Per metric and hour: every (value, computed_at) a window answered, silence counting only from coverage."""
	answers: dict[tuple[str, int], list[tuple[int | None, int]]] = {}
	for batch in batches:
		for window in batch.aggregate_windows:
			values = {bucket.start_ms: bucket.value for bucket in window.buckets}
			for hour in range(window.start_ms, window.end_ms, HOUR):
				if hour in values:
					answers.setdefault((window.metric, hour), []).append((values[hour], window.computed_at_ms))
				elif batch.coverage_start_ms is None or hour >= batch.coverage_start_ms:
					answers.setdefault((window.metric, hour), []).append((None, window.computed_at_ms))
	return answers


def _content(version: RecordVersion) -> tuple[Any, ...]:
	source = version.source.key()
	return (
		str(version.record_type),
		source,
		version.start_ms,
		version.start_offset_s,
		version.end_ms,
		version.end_offset_s,
		version.last_modified_ms,
		version.payload,
	)


def _label(batches: list[IngestBatch]) -> None:
	seen_versions: dict[Any, set[int]] = {}
	first_deletion: dict[Any, int] = {}
	for index, batch in enumerate(batches):
		for deletion in batch.deletions:
			first_deletion.setdefault(deletion.hc_id, index)
		for record in batch.records:
			seen_versions.setdefault(record.hc_id, set()).add(record.last_modified_ms)
			if first_deletion.get(record.hc_id, index + 1) < index:
				event("deletion arrives before an insert")
	if any(len(timestamps) > 1 for timestamps in seen_versions.values()):
		event("one id, several last_modified")


class ConvergencePropertyTestCase(HypothesisTestCase):
	databases = HEALTH_DATABASES

	@pytest.mark.property
	@given(batches=st.lists(_batches, min_size=1, max_size=5), data=st.data())
	@settings(max_examples=200, deadline=None)
	def test_any_order_and_duplication_converges(self, batches: list[IngestBatch], data: st.DataObject):
		extras = data.draw(st.lists(st.sampled_from(batches), max_size=len(batches)), label="duplicates")
		reshuffled = data.draw(st.permutations([*batches, *extras]), label="order")
		_label(batches)
		_label(reshuffled)

		for batch in batches:
			apply_batch(OWNER_A, batch)
		for batch in reshuffled:
			apply_batch(OWNER_B, batch)

		final = store(OWNER_A)
		assert store(OWNER_B) == final

		allowed, tombstones = _expected_records(batches)
		assert final["tombstones"] == tombstones
		assert set(final["records"]) == set(allowed)
		for hc_id, row in final["records"].items():
			assert row in [_content(candidate) for candidate in allowed[hc_id]]

		answers = _expected_aggregates(batches)
		assert set(final["aggregates"]) == set(answers)
		for key, (value, _origins, computed_at) in final["aggregates"].items():
			newest = max(at for _, at in answers[key])
			values_then = [answer for answer, at in answers[key] if at == newest]
			assert computed_at == newest
			present = [answer for answer in values_then if answer is not None]
			assert value == (max(present) if present else None)


def _cap_batch(steps: int, deletions: int, window_hours: list[int]) -> dict[str, Any]:
	return {
		"coverage_start_ms": None,
		"steps": [steps_wire(n) for n in range(steps)],
		"deletions": [{"hc_id": str(uid(n)), "observed_at_ms": 1} for n in range(deletions)],
		"aggregate_windows": [
			{"metric": "steps_count_total", "start_ms": 0, "end_ms": hours * HOUR, "computed_at_ms": 1, "buckets": []}
			for hours in window_hours
		],
	}


@pytest.mark.property
@given(
	total=st.integers(MAX_INGEST_ITEMS - 2, MAX_INGEST_ITEMS + 2),
	steps=st.integers(0, 3),
	window_hours=st.lists(st.integers(1, 744), max_size=6),
)
@settings(max_examples=25, deadline=None)
def test_a_batch_is_accepted_iff_its_items_fit(total: int, steps: int, window_hours: list[int]):
	deletions = max(0, total - steps - sum(window_hours))
	items = steps + deletions + sum(window_hours)
	serializer = HealthIngestSerializer(data=_cap_batch(steps, deletions, window_hours))

	accepted = serializer.is_valid()

	assert accepted is (items <= MAX_INGEST_ITEMS), serializer.errors
	if not accepted:
		with pytest.raises(ValidationError, match="at most 5000 items"):
			HealthIngestSerializer(data=_cap_batch(steps, deletions, window_hours)).is_valid(raise_exception=True)
