"""Health rows follow their owner's account: a soft delete removes them in its own transaction, and
a batch whose owner was deleted mid-request is refused. Hard deletes cascade (test_models.py)."""

import json
from typing import Any
from unittest.mock import patch

import pytest
from django.db import transaction
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient

from accounts.models import User
from commons.test_utils import login_client
from commons.utils import create_users
from health.ingest import Deletion, IngestBatch, IngestOutcome, OwnerGoneError, apply_batch
from health.models import AggregateMetric, HealthAggregate, HealthDeletion, HealthIngestBatch, HealthRecord
from health.tests.support import batch, owner, steps_version, uid, window

FULL = {"HealthRecord": 1, "HealthDeletion": 1, "HealthAggregate": 2, "HealthIngestBatch": 1}
EMPTY = dict.fromkeys(FULL, 0)


class _RolledBackError(Exception):
	pass


def _give_health_data(owner_id: int) -> None:
	apply_batch(
		owner_id,
		batch(
			steps_version(uid(1), last_modified=1),
			Deletion(uid(2), observed_at_ms=1),
			window(AggregateMetric.STEPS_COUNT_TOTAL, 0, 2, computed_at=1, values={0: 5}),
		),
	)


def _rows(owner_id: int) -> dict[str, int]:
	models = (HealthRecord, HealthDeletion, HealthAggregate, HealthIngestBatch)
	return {model.__name__: model.objects.filter(owner_id=owner_id).count() for model in models}


class SoftDeleteTestCase(TestCase):
	def setUp(self):
		self.user, self.other = owner(), owner()
		_give_health_data(self.user)
		_give_health_data(self.other)

	def test_deleting_an_account_through_the_api_removes_only_its_rows(self):
		user = create_users()[0]
		_give_health_data(user.pk)
		client = login_client(APIClient(), user.get_username())

		assert client.delete(reverse("users-detail", kwargs={"pk": user.pk})).status_code == status.HTTP_204_NO_CONTENT
		assert User._base_manager.get(pk=user.pk).date_deleted is not None
		assert _rows(user.pk) == EMPTY
		assert _rows(self.other) == FULL

	def test_a_rolled_back_deletion_keeps_the_rows(self):
		with pytest.raises(_RolledBackError), transaction.atomic():
			User.objects.get(pk=self.user).delete()
			assert _rows(self.user) == EMPTY
			raise _RolledBackError

		assert User.objects.filter(pk=self.user).exists()
		assert _rows(self.user) == FULL

	def test_deactivation_alone_keeps_the_rows(self):
		user = User.objects.get(pk=self.user)
		user.is_active = False
		user.save()

		assert _rows(self.user) == FULL


class LiveOwnerGuardTestCase(TestCase):
	def test_a_deleted_or_deactivated_owner_is_refused_and_nothing_is_stored(self):
		changes: list[tuple[str, dict[str, Any]]] = [
			("deleted", {"date_deleted": timezone.now()}),
			("deactivated", {"is_active": False}),
		]
		for label, change in changes:
			with self.subTest(label):
				user = owner()
				User._base_manager.filter(pk=user).update(**change)

				with pytest.raises(OwnerGoneError, match=f"User {user} was deleted or deactivated"):
					_give_health_data(user)

				assert _rows(user) == EMPTY

	def test_a_deletion_between_authentication_and_ingest_is_a_401(self):
		user = create_users()[0]
		client = login_client(APIClient(), user.get_username())

		def deleted_mid_request(owner_id: int, batch: IngestBatch) -> IngestOutcome:
			# The deletion commits after the session authenticated this request.
			User._base_manager.filter(pk=owner_id).update(is_active=False, date_deleted=timezone.now())
			return apply_batch(owner_id, batch)

		with patch("health.views.apply_batch", deleted_mid_request):
			response = client.post(
				reverse("health-ingest"), data=json.dumps({"coverage_start_ms": None}), content_type="application/json"
			)

		assert response.status_code == status.HTTP_401_UNAUTHORIZED
		assert response["WWW-Authenticate"] == "Session"
		assert _rows(user.pk) == EMPTY
