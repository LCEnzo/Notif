"""Delete health rows whose owner no longer exists, after a purge that failed."""

from itertools import batched
from typing import Any

from django.core.management.base import BaseCommand

from accounts.models import User
from health.owners import owners_with_rows, purge_owner

# Ids per IN (...) lookup; well under SQLite's variable limit.
_CHUNK = 500


class Command(BaseCommand):
	help = "Delete the health rows of users who no longer exist."

	def handle(self, *args: Any, **options: Any) -> None:
		owner_ids = sorted(owners_with_rows())
		live: set[int] = set()
		for chunk in batched(owner_ids, _CHUNK, strict=False):
			live.update(User.objects.filter(pk__in=chunk).values_list("pk", flat=True))
		orphans = [owner_id for owner_id in owner_ids if owner_id not in live]
		for owner_id in orphans:
			self.stdout.write(f"owner {owner_id}: {purge_owner(owner_id)} rows deleted")
		self.stdout.write(f"{len(orphans)} orphaned owners purged")
