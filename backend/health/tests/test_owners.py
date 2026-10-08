"""A deleted user's health rows go when the deletion commits, and stay when it rolls back.

Users are soft-deleted by ``User.delete`` (the API path) and hard-deleted by
``actually_delete`` or a queryset delete (the admin's bulk action); all three count.
"""

import json
import logging
from collections.abc import Callable
from io import StringIO
from typing import Any
from unittest.mock import patch

import pytest
from django.core.management import call_command
from django.db import OperationalError, transaction
from django.db.models import QuerySet
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient

from accounts.models import User
from commons.test_utils import login_client
from commons.utils import create_users
from health.ingest import Deletion, IngestBatch, IngestOutcome, OwnerGoneError, apply_batch, apply_batch_for_live_owner
from health.models import AggregateMetric, HealthSource
from health.owners import OWNED_MODELS
from health.tests.support import HEALTH_DATABASES, batch, steps_version, uid, window


class _RolledBackError(Exception):
	pass


def _give_health_data(owner_id: int) -> None:
	apply_batch(
		owner_id,
		batch(
			steps_version(uid(owner_id * 10 + 1), last_modified=1),
			Deletion(uid(owner_id * 10 + 2), observed_at_ms=1),
			window(AggregateMetric.STEPS_COUNT_TOTAL, 0, 2, computed_at=1, values={0: 5}),
		),
	)


def _rows(owner_id: int) -> dict[str, int]:
	return {model.__name__: model._default_manager.filter(owner_id=owner_id).count() for model in OWNED_MODELS}


FULL = {"HealthRecord": 1, "HealthDeletion": 1, "HealthAggregate": 2, "HealthIngestBatch": 1}
EMPTY = dict.fromkeys(FULL, 0)

_DELETIONS: dict[str, Callable[[User], object]] = {
	"soft (User.delete)": lambda user: user.delete(),
	"hard (actually_delete)": lambda user: user.actually_delete(),
	"queryset (admin bulk delete)": lambda user: User._base_manager.filter(pk=user.pk).delete(),
}


class UserDeletionTestCase(TestCase):
	databases = HEALTH_DATABASES

	def setUp(self):
		self.user, self.other, *_ = create_users()
		_give_health_data(self.user.pk)
		_give_health_data(self.other.pk)

	def test_every_kind_of_committed_deletion_removes_only_that_users_rows(self):
		for label, delete in _DELETIONS.items():
			with self.subTest(label):
				user = User.objects.create_user(email=f"{label[:4]}@example.com", username=label[:4], password="x" * 12)
				_give_health_data(user.pk)

				with self.captureOnCommitCallbacks(execute=True):
					delete(user)

				assert _rows(user.pk) == EMPTY
				assert _rows(self.other.pk) == FULL
		# Sources are shared across owners, so they stay.
		assert HealthSource.objects.exists()

	def test_nothing_is_removed_before_the_deletion_commits(self):
		with self.captureOnCommitCallbacks() as callbacks:
			self.user.delete()
			assert _rows(self.user.pk) == FULL

		assert len(callbacks) == 1
		callbacks[0]()
		assert _rows(self.user.pk) == EMPTY

	def test_a_rolled_back_deletion_keeps_the_rows(self):
		owner_id = self.user.pk
		for label, delete in _DELETIONS.items():
			with (
				self.subTest(label),
				self.captureOnCommitCallbacks(execute=True) as callbacks,
				pytest.raises(_RolledBackError),
				transaction.atomic(),
			):
				# A fresh instance: a deletion leaves the in-memory one changed even when it rolls back.
				delete(User._base_manager.get(pk=owner_id))
				raise _RolledBackError

			assert callbacks == []
			assert User.objects.filter(pk=owner_id).exists()
			assert _rows(owner_id) == FULL

	def test_deactivation_alone_keeps_the_rows(self):
		self.user.is_active = False
		with self.captureOnCommitCallbacks(execute=True):
			self.user.save()

		assert _rows(self.user.pk) == FULL

	def test_a_failed_purge_is_logged_and_the_sweep_finishes_it(self):
		def locked(self: QuerySet[Any]) -> None:
			raise OperationalError("database is locked")

		with (
			patch.object(QuerySet, "delete", locked),
			self.assertLogs("health.owners", level=logging.ERROR) as logs,
			self.captureOnCommitCallbacks(execute=True),
		):
			self.user.delete()

		assert f"deleted user {self.user.pk} failed" in logs.output[0]
		assert not User.objects.filter(pk=self.user.pk).exists()
		assert _rows(self.user.pk) == FULL

		out = StringIO()
		call_command("purge_health_orphans", stdout=out)

		assert _rows(self.user.pk) == EMPTY
		assert _rows(self.other.pk) == FULL
		assert out.getvalue().endswith("1 orphaned owners purged\n")

	def test_the_sweep_leaves_live_and_deactivated_owners_alone(self):
		User.objects.filter(pk=self.other.pk).update(is_active=False)
		out = StringIO()
		call_command("purge_health_orphans", stdout=out)

		assert _rows(self.user.pk) == FULL
		assert _rows(self.other.pk) == FULL
		assert out.getvalue() == "0 orphaned owners purged\n"


@pytest.mark.django_db(transaction=True, databases=HEALTH_DATABASES)
def test_deleting_an_account_through_the_api_removes_its_health_rows():
	user, other, *_ = create_users()
	_give_health_data(user.pk)
	_give_health_data(other.pk)
	client = login_client(APIClient(), user.get_username())

	response = client.delete(reverse("users-detail", kwargs={"pk": user.pk}))

	assert response.status_code == status.HTTP_204_NO_CONTENT
	assert User._base_manager.get(pk=user.pk).date_deleted is not None
	assert _rows(user.pk) == EMPTY
	assert _rows(other.pk) == FULL


@pytest.mark.django_db(transaction=True, databases=HEALTH_DATABASES)
def test_a_really_rolled_back_deletion_keeps_the_rows():
	user = create_users()[0]
	_give_health_data(user.pk)

	with pytest.raises(_RolledBackError), transaction.atomic():
		user.delete()
		raise _RolledBackError

	assert User.objects.filter(pk=user.pk).exists()
	assert _rows(user.pk) == FULL


class LiveOwnerGuardTestCase(TestCase):
	"""A batch whose owner was deleted after authenticating must not outlive the purge."""

	databases = HEALTH_DATABASES

	def setUp(self):
		self.user = create_users()[0]

	def test_a_live_owner_is_stored(self):
		apply_batch_for_live_owner(self.user.pk, batch(steps_version(uid(1), last_modified=1)))

		assert _rows(self.user.pk)["HealthRecord"] == 1

	def test_a_deleted_or_deactivated_owner_is_refused_and_nothing_is_stored(self):
		changes: list[tuple[str, dict[str, Any]]] = [
			("deleted", {"date_deleted": timezone.now()}),
			("deactivated", {"is_active": False}),
		]
		for label, change in changes:
			with self.subTest(label):
				user = User.objects.create_user(email=f"{label}@example.com", username=label, password="x" * 12)
				User._base_manager.filter(pk=user.pk).update(**change)

				with pytest.raises(OwnerGoneError, match=f"User {user.pk} was deleted or deactivated"):
					apply_batch_for_live_owner(user.pk, batch(steps_version(uid(1), last_modified=1)))

				assert _rows(user.pk) == EMPTY

	def test_a_deletion_between_authentication_and_ingest_is_a_401(self):
		client = login_client(APIClient(), self.user.get_username())

		def deleted_mid_request(owner_id: int, batch: IngestBatch) -> IngestOutcome:
			# The deletion commits after the session authenticated this request.
			User._base_manager.filter(pk=owner_id).update(is_active=False, date_deleted=timezone.now())
			return apply_batch_for_live_owner(owner_id, batch)

		with patch("health.views.apply_batch_for_live_owner", deleted_mid_request):
			response = client.post(
				reverse("health-ingest"), data=json.dumps({"coverage_start_ms": None}), content_type="application/json"
			)

		assert response.status_code == status.HTTP_401_UNAUTHORIZED
		assert response["WWW-Authenticate"] == "Session"
		assert _rows(self.user.pk) == EMPTY
