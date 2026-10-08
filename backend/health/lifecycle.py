"""Health rows follow their owner's account.

A hard delete cascades through the owner foreign keys. ``User.delete`` is a soft delete that
only sets ``date_deleted``, so this hook removes the rows inside that save's transaction: a
rolled-back deletion keeps them, and no state exists where the account is gone but its rows
remain. Deactivation alone keeps them.
"""

from typing import Any

from accounts.models import User
from health.models import HealthAggregate, HealthDeletion, HealthIngestBatch, HealthRecord


def delete_rows_of_soft_deleted_user(sender: type[User], instance: User, **kwargs: Any) -> None:
	# Every later save of a deleted user runs this again, which finds nothing to delete.
	if instance.date_deleted is None:
		return
	HealthRecord.objects.filter(owner=instance).delete()
	HealthDeletion.objects.filter(owner=instance).delete()
	HealthAggregate.objects.filter(owner=instance).delete()
	HealthIngestBatch.objects.filter(owner=instance).delete()
