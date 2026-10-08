"""apply_batch against the store: version order, tombstones, aggregates, sources, atomicity."""

from unittest.mock import patch

import pytest
from django.test import TestCase

from health import ingest
from health.ingest import Deletion, Source, apply_batch
from health.models import AggregateMetric, HealthIngestBatch, HealthRecord, HealthSource
from health.tests.support import (
	HEALTH_DATABASES,
	HOUR,
	ORIGIN,
	batch,
	steps_version,
	store,
	uid,
	window,
)

OWNER = 7
OTHER_OWNER = 8
STEPS = AggregateMetric.STEPS_COUNT_TOTAL
SLEEP = AggregateMetric.SLEEP_DURATION_TOTAL


class RecordVersionTestCase(TestCase):
	databases = HEALTH_DATABASES

	def test_a_new_record_is_written_and_a_replay_changes_nothing(self):
		first = apply_batch(OWNER, batch(steps_version(uid(1), last_modified=10)))
		snapshot = store(OWNER)
		replay = apply_batch(OWNER, batch(steps_version(uid(1), last_modified=10)))

		assert (first.records_written, first.records_ignored) == (1, 0)
		assert (replay.records_written, replay.records_ignored) == (0, 1)
		assert store(OWNER) == snapshot

	def test_a_newer_version_replaces_and_an_older_one_does_not(self):
		apply_batch(OWNER, batch(steps_version(uid(1), last_modified=10, count=1)))
		newer = apply_batch(OWNER, batch(steps_version(uid(1), last_modified=11, count=2)))
		older = apply_batch(OWNER, batch(steps_version(uid(1), last_modified=9, count=3)))

		assert newer.records_written == 1
		assert older.records_ignored == 1
		assert HealthRecord.objects.get(hc_id=uid(1)).payload == {"count": 2}

	def test_equal_timestamps_resolve_to_the_same_version_in_either_order(self):
		low = steps_version(uid(1), last_modified=10, count=1)
		high = steps_version(uid(1), last_modified=10, count=2)

		apply_batch(OWNER, batch(low))
		apply_batch(OWNER, batch(high))
		apply_batch(OTHER_OWNER, batch(high))
		apply_batch(OTHER_OWNER, batch(low))

		assert store(OWNER) == store(OTHER_OWNER)
		assert HealthRecord.objects.get(owner_id=OWNER).payload == {"count": 2}

	def test_duplicates_within_one_batch_keep_the_newest(self):
		outcome = apply_batch(
			OWNER,
			batch(steps_version(uid(1), last_modified=12, count=2), steps_version(uid(1), last_modified=11, count=1)),
		)

		assert (outcome.records_written, outcome.records_ignored) == (1, 1)
		assert HealthRecord.objects.get(hc_id=uid(1)).last_modified_ms == 12

	def test_owners_do_not_share_ids(self):
		apply_batch(OWNER, batch(steps_version(uid(1), last_modified=10, count=1)))
		apply_batch(OTHER_OWNER, batch(steps_version(uid(1), last_modified=10, count=5)))
		apply_batch(OTHER_OWNER, batch(Deletion(uid(1), observed_at_ms=20)))

		assert HealthRecord.objects.get(owner_id=OWNER).payload == {"count": 1}
		assert not HealthRecord.objects.filter(owner_id=OTHER_OWNER).exists()


class DeletionTestCase(TestCase):
	databases = HEALTH_DATABASES

	def test_a_deletion_removes_versions_modified_at_or_before_it(self):
		for last_modified, survives in [(19, False), (20, False), (21, True)]:
			with self.subTest(last_modified=last_modified):
				hc_id = uid(last_modified)
				apply_batch(OWNER, batch(steps_version(hc_id, last_modified=last_modified)))
				outcome = apply_batch(OWNER, batch(Deletion(hc_id, observed_at_ms=20)))

				assert HealthRecord.objects.filter(hc_id=hc_id).exists() is survives
				assert outcome.records_deleted == (0 if survives else 1)

	def test_a_deletion_that_arrives_first_suppresses_older_versions_only(self):
		apply_batch(OWNER, batch(Deletion(uid(1), observed_at_ms=20)))

		stale = apply_batch(OWNER, batch(steps_version(uid(1), last_modified=20)))
		assert stale.records_ignored == 1
		assert not HealthRecord.objects.filter(hc_id=uid(1)).exists()

		reinserted = apply_batch(OWNER, batch(steps_version(uid(1), last_modified=21)))
		assert reinserted.records_written == 1
		assert HealthRecord.objects.filter(hc_id=uid(1)).exists()

	def test_a_tombstone_keeps_the_latest_deletion(self):
		apply_batch(OWNER, batch(Deletion(uid(1), observed_at_ms=30)))
		apply_batch(OWNER, batch(Deletion(uid(1), observed_at_ms=20), Deletion(uid(1), observed_at_ms=25)))

		assert store(OWNER)["tombstones"] == {uid(1): 30}

	def test_a_deletion_and_a_newer_version_in_one_batch_keep_the_version(self):
		apply_batch(OWNER, batch(steps_version(uid(1), last_modified=10)))
		outcome = apply_batch(
			OWNER, batch(Deletion(uid(1), observed_at_ms=15), steps_version(uid(1), last_modified=16))
		)

		assert (outcome.records_written, outcome.records_deleted) == (1, 0)
		assert HealthRecord.objects.get(hc_id=uid(1)).last_modified_ms == 16


class SourceTestCase(TestCase):
	databases = HEALTH_DATABASES

	def test_records_share_one_row_per_distinct_source(self):
		watch = Source(ORIGIN, "automatically_recorded", "watch", "Google", "Pixel Watch 2")
		apply_batch(
			OWNER,
			batch(
				steps_version(uid(1), last_modified=1, source=watch),
				steps_version(uid(2), last_modified=1, source=watch),
				steps_version(uid(3), last_modified=1),
			),
		)
		apply_batch(OTHER_OWNER, batch(steps_version(uid(4), last_modified=1, source=watch)))

		assert HealthSource.objects.count() == 2
		assert store(OWNER)["records"][uid(1)][1] == (
			ORIGIN,
			"automatically_recorded",
			"watch",
			"Google",
			"Pixel Watch 2",
		)

	def test_a_missing_device_and_a_device_without_details_stay_distinct(self):
		apply_batch(OWNER, batch(steps_version(uid(1), last_modified=1)))
		bare = Source(ORIGIN, "automatically_recorded", "unknown", None, None)
		apply_batch(OWNER, batch(steps_version(uid(2), last_modified=1, source=bare)))

		assert HealthSource.objects.count() == 2
		assert Source.from_row(HealthRecord.objects.get(hc_id=uid(2)).source) == bare

	def test_device_details_without_a_device_are_refused(self):
		with pytest.raises(ValueError, match="without a device"):
			Source(ORIGIN, "unknown", None, "Google", None)


class AggregateTestCase(TestCase):
	databases = HEALTH_DATABASES

	def test_hours_without_a_bucket_are_stored_as_empty(self):
		outcome = apply_batch(OWNER, batch(window(STEPS, 0, 3, computed_at=5, values={1: 40})))

		assert store(OWNER)["aggregates"] == {
			(STEPS, 0): (None, (), 5),
			(STEPS, HOUR): (40, (ORIGIN,), 5),
			(STEPS, 2 * HOUR): (None, (), 5),
		}
		assert (outcome.aggregates_written, outcome.aggregates_ignored) == (3, 0)

	def test_silence_before_coverage_start_is_not_stored(self):
		outcome = apply_batch(
			OWNER, batch(window(STEPS, 0, 3, computed_at=5, values={0: 7}), coverage_start_ms=HOUR + 1)
		)

		# Hour 0 holds a value HC did return; hour 1 starts before the floor, so its silence means nothing.
		assert store(OWNER)["aggregates"] == {(STEPS, 0): (7, (ORIGIN,), 5), (STEPS, 2 * HOUR): (None, (), 5)}
		assert outcome.aggregates_ignored == 1

	def test_the_newest_answer_per_hour_wins_in_either_order(self):
		old = window(STEPS, 0, 1, computed_at=5, values={0: 40})
		new_empty = window(STEPS, 0, 1, computed_at=6, values={})

		apply_batch(OWNER, batch(old))
		apply_batch(OWNER, batch(new_empty))
		apply_batch(OTHER_OWNER, batch(new_empty))
		late = apply_batch(OTHER_OWNER, batch(old))

		assert store(OWNER) == store(OTHER_OWNER)
		assert store(OWNER)["aggregates"] == {(STEPS, 0): (None, (), 6)}
		assert late.aggregates_ignored == 1

	def test_equal_computation_times_prefer_a_value_then_the_larger(self):
		apply_batch(OWNER, batch(window(SLEEP, 0, 1, computed_at=5, values={})))
		apply_batch(OWNER, batch(window(SLEEP, 0, 1, computed_at=5, values={0: 10})))
		apply_batch(OWNER, batch(window(SLEEP, 0, 1, computed_at=5, values={0: 9})))

		assert store(OWNER)["aggregates"] == {(SLEEP, 0): (10, (ORIGIN,), 5)}

	def test_metrics_do_not_overwrite_each_other(self):
		apply_batch(OWNER, batch(window(STEPS, 0, 1, 5, {0: 1}), window(SLEEP, 0, 1, 5, {0: 2})))

		assert set(store(OWNER)["aggregates"]) == {(STEPS, 0), (SLEEP, 0)}


class BatchTestCase(TestCase):
	databases = HEALTH_DATABASES

	def test_each_batch_is_logged_with_its_coverage_and_counts(self):
		outcome = apply_batch(
			OWNER,
			batch(
				steps_version(uid(1), last_modified=1),
				Deletion(uid(2), observed_at_ms=1),
				window(STEPS, 0, 4, 5, {}),
				coverage_start_ms=123,
			),
		)

		logged = HealthIngestBatch.objects.get(pk=outcome.batch_id)
		assert (logged.owner_id, logged.coverage_start_ms) == (OWNER, 123)
		assert (logged.record_count, logged.deletion_count, logged.aggregate_hour_count) == (1, 1, 4)

	def test_a_failure_part_way_leaves_nothing_behind(self):
		with (
			patch.object(ingest, "_apply_aggregates", side_effect=RuntimeError("disk full")),
			pytest.raises(RuntimeError, match="disk full"),
		):
			apply_batch(OWNER, batch(steps_version(uid(1), last_modified=1), Deletion(uid(2), observed_at_ms=1)))

		# Records and tombstones were written before the failure; the health transaction must undo them.
		assert store(OWNER) == {"records": {}, "tombstones": {}, "aggregates": {}}
		assert not HealthIngestBatch.objects.exists()

	def test_lookups_and_writes_span_several_chunks(self):
		versions = [steps_version(uid(n), last_modified=1) for n in range(1, 1_202)]
		apply_batch(OWNER, batch(*versions))
		outcome = apply_batch(OWNER, batch(*[Deletion(uid(n), observed_at_ms=1) for n in range(1, 1_202)]))

		assert outcome.records_deleted == 1_201
		assert not HealthRecord.objects.exists()
