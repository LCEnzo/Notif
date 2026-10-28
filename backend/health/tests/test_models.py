"""Storage rules the database itself enforces."""

from uuid import uuid4

import pytest
from django.db import IntegrityError, transaction

from accounts.models import User
from health.models import HealthAggregate, HealthDeletion, HealthIngestBatch, HealthRecord, HealthSource

pytestmark = pytest.mark.django_db

OWNED = (HealthRecord, HealthDeletion, HealthAggregate, HealthIngestBatch)


def _user(name: str) -> User:
	return User.objects.create_user(username=name, email=f"{name}@example.com", password="x" * 12)


def _source(**overrides: str) -> HealthSource:
	fields = {"data_origin": "com.example", "recording_method": "unknown", **overrides}
	return HealthSource.objects.create(**fields)


def _fill(owner: User, source: HealthSource) -> None:
	HealthRecord.objects.create(
		owner=owner, hc_id=uuid4(), record_type="steps", source=source, start_ms=0, last_modified_ms=0, payload={}
	)
	HealthDeletion.objects.create(owner=owner, hc_id=uuid4(), observed_at_ms=0)
	HealthAggregate.objects.create(
		owner=owner, metric="steps_count_total", bucket_start_ms=0, value=1, computed_at_ms=0
	)
	HealthIngestBatch.objects.create(owner=owner, record_count=1, deletion_count=1, aggregate_hour_count=1)


def test_a_hard_deleted_user_takes_only_their_rows():
	source = _source()
	gone, kept = _user("gone"), _user("kept")
	_fill(gone, source)
	_fill(kept, source)

	gone.actually_delete()

	assert [model.objects.count() for model in OWNED] == [1, 1, 1, 1]
	assert {model.objects.get().owner_id for model in OWNED} == {kept.pk}
	# Shared by every owner, so it stays.
	assert HealthSource.objects.exists()


@pytest.mark.parametrize(
	"build",
	[
		pytest.param(lambda: _source(device_manufacturer="Google"), id="device details without a device"),
		pytest.param(
			lambda: HealthRecord.objects.create(
				owner=_user("owner"), hc_id=uuid4(), record_type="steps", source=_source(),
				start_ms=5, end_ms=5, last_modified_ms=0, payload={},
			),
			id="end not after start",
		),
	],
)  # fmt: skip
def test_the_database_refuses(build):
	with pytest.raises(IntegrityError), transaction.atomic():
		build()
