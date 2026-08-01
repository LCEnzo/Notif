from __future__ import annotations

from typing import Any

from django.core.management.base import BaseCommand

from accounts.device_sessions import cleanup_device_sessions


class Command(BaseCommand):
	help = "Delete device-session rows that have been dead (revoked or expired) past the retention window."

	def handle(self, *args: Any, **options: Any) -> None:
		deleted = cleanup_device_sessions()
		self.stdout.write(f"Deleted {deleted.sessions_deleted} dead device session(s).")
