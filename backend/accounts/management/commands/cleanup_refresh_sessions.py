from __future__ import annotations

from typing import Any

from django.core.management.base import BaseCommand

from accounts.refresh_sessions import cleanup_refresh_sessions


class Command(BaseCommand):
	help = "Delete expired or revoked refresh-session families and their token records."

	def handle(self, *args: Any, **options: Any) -> None:
		deleted = cleanup_refresh_sessions()
		self.stdout.write(f"Deleted {deleted} refresh session family/families.")
