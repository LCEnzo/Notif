"""apply_batch at the exact boundaries of its rules; test_properties.py covers order and duplication."""

from unittest.mock import patch

import pytest
from django.test import TestCase

from health import ingest
from health.ingest import Deletion, Source, apply_batch
from health.models import AggregateMetric, HealthIngestBatch, HealthRecord, HealthSource
from health.tests.support import HOUR, ORIGIN, batch, owner, steps_version, store, uid, window

STEPS = AggregateMetric.STEPS_COUNT_TOTAL


class RecordTestCase(TestCase):
	def setUp(self):
		self.owner = owner()

	def test_a_replay_writes_nothing(self):
		first = apply_batch(self.owner, batch(steps_version(uid(1), last_modified=10)))
		snapshot = store(self.owner)
		replay = apply_batch(self.owner, batch(steps_version(uid(1), last_modified=10)))

		assert (first.records_written, replay.records_written) == (1, 0)
		assert store(self.owner) == snapshot

	def test_a_deletion_removes_versions_modified_at_or_before_it(self):
		for last_modified, survives in [(19, False), (20, False), (21, True)]:
			with self.subTest(last_modified=last_modified):
				hc_id = uid(last_modified)
				apply_batch(self.owner, batch(steps_version(hc_id, last_modified=last_modified)))
				outcome = apply_batch(self.owner, batch(Deletion(hc_id, observed_at_ms=20)))

				assert HealthRecord.objects.filter(hc_id=hc_id).exists() is survives
				assert outcome.records_deleted == (0 if survives else 1)

	def test_a_deletion_that_arrives_first_suppresses_older_versions_only(self):
		apply_batch(self.owner, batch(Deletion(uid(1), observed_at_ms=20)))

		assert apply_batch(self.owner, batch(steps_version(uid(1), last_modified=20))).records_written == 0
		assert apply_batch(self.owner, batch(steps_version(uid(1), last_modified=21))).records_written == 1

	def test_a_deletion_and_a_newer_version_in_one_batch_keep_the_version(self):
		apply_batch(self.owner, batch(steps_version(uid(1), last_modified=10)))
		outcome = apply_batch(
			self.owner, batch(Deletion(uid(1), observed_at_ms=15), steps_version(uid(1), last_modified=16))
		)

		assert (outcome.records_written, outcome.records_deleted) == (1, 0)

	def test_owners_do_not_share_ids(self):
		other = owner()
		apply_batch(self.owner, batch(steps_version(uid(1), last_modified=10, count=1)))
		apply_batch(other, batch(steps_version(uid(1), last_modified=10, count=5)))
		apply_batch(other, batch(Deletion(uid(1), observed_at_ms=20)))

		assert HealthRecord.objects.get(owner_id=self.owner).payload == {"count": 1}
		assert not HealthRecord.objects.filter(owner_id=other).exists()

	def test_sources_are_shared_and_a_missing_device_differs_from_a_bare_one(self):
		bare = Source(ORIGIN, "automatically_recorded", "unknown", None, None)
		apply_batch(
			self.owner,
			batch(
				steps_version(uid(1), last_modified=1),
				steps_version(uid(2), last_modified=1),
				steps_version(uid(3), last_modified=1, source=bare),
			),
		)

		assert HealthSource.objects.count() == 2
		assert store(self.owner)["records"][uid(3)][1] == bare.key()


class AggregateAndBatchTestCase(TestCase):
	def setUp(self):
		self.owner = owner()

	def test_hours_without_a_bucket_are_zeros_except_before_coverage(self):
		apply_batch(self.owner, batch(window(STEPS, 0, 3, computed_at=5, values={0: 7}), coverage_start_ms=HOUR + 1))

		# Hour 0 holds a value HC returned; hour 1 starts before coverage, so its silence means nothing.
		assert store(self.owner)["aggregates"] == {(STEPS, 0): (7, (ORIGIN,), 5), (STEPS, 2 * HOUR): (None, (), 5)}

	def test_each_batch_is_logged_with_its_coverage_and_counts(self):
		outcome = apply_batch(
			self.owner,
			batch(
				steps_version(uid(1), last_modified=1),
				Deletion(uid(2), observed_at_ms=1),
				window(STEPS, 0, 4, 5, {}),
				coverage_start_ms=123,
			),
		)

		logged = HealthIngestBatch.objects.get(pk=outcome.batch_id)
		assert (logged.owner_id, logged.coverage_start_ms) == (self.owner, 123)
		assert (logged.record_count, logged.deletion_count, logged.aggregate_hour_count) == (1, 1, 4)
		# Hour 0 starts before coverage_start_ms, so its silence is not stored.
		assert outcome.aggregates_written == 3

	def test_a_failure_part_way_leaves_nothing_behind(self):
		with (
			patch.object(ingest, "_apply_aggregates", side_effect=RuntimeError("disk full")),
			pytest.raises(RuntimeError, match="disk full"),
		):
			apply_batch(self.owner, batch(steps_version(uid(1), last_modified=1), Deletion(uid(2), observed_at_ms=1)))

		assert store(self.owner) == {"records": {}, "tombstones": {}, "aggregates": {}}
		assert not HealthIngestBatch.objects.exists()

	def test_a_batch_at_the_item_cap_applies_in_one_go(self):
		# 5,000 ids in one IN (...): no chunking needed under SQLite's variable limit.
		apply_batch(self.owner, batch(*[steps_version(uid(n), last_modified=1) for n in range(5_000)]))
		outcome = apply_batch(self.owner, batch(*[Deletion(uid(n), observed_at_ms=1) for n in range(5_000)]))

		assert outcome.records_deleted == 5_000
