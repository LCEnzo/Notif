"""Removing a user's health rows when the user is deleted.

The user table is in the other database, so no foreign key cascades. Users are
soft-deleted (``User.delete`` sets ``date_deleted``) or hard-deleted (``actually_delete``,
queryset deletes); either schedules the purge for the deleting transaction's commit,
so a rolled-back deletion keeps the data. Deactivation alone keeps it. A purge that
fails is logged with the owner id; ``manage.py purge_health_orphans`` finishes it.
"""

import logging
from functools import partial
from typing import Any

from django.db import Error as DbError
from django.db import models, router, transaction

from accounts.models import User
from health.models import HealthAggregate, HealthDeletion, HealthIngestBatch, HealthRecord

logger = logging.getLogger(__name__)

# Every model with an owner_id. HealthSource rows are shared across owners and stay.
OWNED_MODELS: tuple[type[models.Model], ...] = (HealthRecord, HealthDeletion, HealthAggregate, HealthIngestBatch)


def purge_owner(owner_id: int) -> int:
	"""Delete every health row of ``owner_id`` in one transaction; returns how many."""
	deleted = 0
	with transaction.atomic(using=router.db_for_write(HealthRecord)):
		for model in OWNED_MODELS:
			count, _ = model._default_manager.filter(owner_id=owner_id).delete()
			deleted += count
	return deleted


def owners_with_rows() -> set[int]:
	owner_ids: set[int] = set()
	for model in OWNED_MODELS:
		owner_ids.update(model._default_manager.values_list("owner_id", flat=True).distinct())
	return owner_ids


def _purge_deleted_user(owner_id: int) -> None:
	try:
		deleted = purge_owner(owner_id)
	except DbError:
		# The user is already gone, so failing the request would help nobody; the log
		# (a SystemEvent) names the owner and the command that finishes the purge.
		logger.exception(
			"Deleting the health rows of deleted user %s failed; run manage.py purge_health_orphans.", owner_id
		)
		return
	logger.info("Deleted %s health rows of deleted user %s.", deleted, owner_id)


def _schedule_purge(owner_id: int, using: str) -> None:
	transaction.on_commit(partial(_purge_deleted_user, owner_id), using=using)


def purge_on_user_hard_delete(sender: type[User], instance: User, using: str, **kwargs: Any) -> None:
	_schedule_purge(instance.pk, using)


def purge_on_user_soft_delete(sender: type[User], instance: User, using: str, **kwargs: Any) -> None:
	# Every save of a soft-deleted user schedules one; the purge is idempotent and cheap once empty.
	if instance.date_deleted is not None:
		_schedule_purge(instance.pk, using)
