import json
from datetime import timedelta
from tempfile import TemporaryDirectory
from unittest.mock import patch

import pytest
from django.core.management import call_command
from django.http import StreamingHttpResponse
from django.test import TestCase
from django.test.utils import override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models.password_reset import (
	PASSWORD_RESET_CODE_MAX_ATTEMPTS,
	PasswordResetCode,
)
from commons.result import Err, Ok
from commons.test_utils import SetupMixin, login_client
from monitoring.models import Link
from ops.models import MaintenanceLock, SystemEvent

pytestmark = pytest.mark.timeout(30)


class OpsApiTestCase(SetupMixin, TestCase):
	def test_events_require_staff_user(self):
		SystemEvent.objects.create(level=SystemEvent.Level.INFO, source="test", kind="log", message="visible")
		client = login_client(APIClient(), self.regular_user.get_username())

		response = client.get("/api/v1/ops/events/")

		self.assertEqual(response.status_code, 403)

	def test_staff_can_list_events(self):
		SystemEvent.objects.create(
			level=SystemEvent.Level.WARNING,
			source="monitoring.services",
			kind="log",
			message="scrape warning",
			details={"link_id": 1},
		)
		client = login_client(APIClient(), self.superuser.get_username())

		response = client.get("/api/v1/ops/events/")

		self.assertEqual(response.status_code, 200)
		self.assertEqual(response.data["results"][0]["message"], "scrape warning")
		self.assertEqual(response.data["results"][0]["details"], {"link_id": 1})

	def test_caddy_logs_require_staff_user(self):
		client = login_client(APIClient(), self.regular_user.get_username())

		response = client.get(reverse("caddy-access-logs"))

		self.assertEqual(response.status_code, 403)

	def test_staff_can_read_caddy_logs(self):
		with TemporaryDirectory() as tmp_dir:
			log_path = f"{tmp_dir}/access.json"
			with open(log_path, "w", encoding="utf-8") as log_file:
				log_file.write(json.dumps({"ts": 1, "request": {"uri": "/old"}, "status": 200}) + "\n")
				log_file.write(json.dumps({"ts": 2, "request": {"uri": "/new"}, "status": 404}) + "\n")

			client = login_client(APIClient(), self.superuser.get_username())
			with override_settings(CADDY_ACCESS_LOG_PATH=log_path):
				response = client.get(reverse("caddy-access-logs"), {"limit": "1"})

		self.assertEqual(response.status_code, 200)
		self.assertEqual(len(response.data["results"]), 1)
		self.assertEqual(response.data["results"][0]["request"]["uri"], "/new")

	def test_missing_caddy_log_returns_empty_results(self):
		client = login_client(APIClient(), self.superuser.get_username())
		with override_settings(CADDY_ACCESS_LOG_PATH="/tmp/notif-missing-caddy-access.json"):
			response = client.get(reverse("caddy-access-logs"))

		self.assertEqual(response.status_code, 200)
		self.assertEqual(response.data["results"], [])

	def test_sqlite_backup_requires_superuser(self):
		client = login_client(APIClient(), self.regular_user.get_username())

		response = client.get(reverse("download-sqlite-backup"))

		self.assertEqual(response.status_code, 403)

	def test_staff_without_superuser_cannot_download_sqlite_backup(self):
		staff_user = self.secondary_user
		staff_user.is_staff = True
		staff_user.is_superuser = False
		staff_user.save(update_fields=["is_staff", "is_superuser"])
		client = login_client(APIClient(), staff_user.get_username())

		response = client.get(reverse("download-sqlite-backup"))

		self.assertEqual(response.status_code, 403)

	def test_superuser_can_download_sqlite_backup(self):
		client = login_client(APIClient(), self.superuser.get_username())

		response = client.get(reverse("download-sqlite-backup"))

		self.assertEqual(response.status_code, 200)
		self.assertEqual(response["Content-Type"], "application/vnd.sqlite3")
		self.assertIn("attachment;", response["Content-Disposition"])
		self.assertEqual(response["Cache-Control"], "no-store")
		self.assertTrue(response.streaming)
		assert isinstance(response, StreamingHttpResponse)

		body = b"".join(response.streaming_content)
		self.assertTrue(body.startswith(b"SQLite format 3"))
		self.assertEqual(int(response["Content-Length"]), len(body))

		audit_events = SystemEvent.objects.filter(source="ops.download_sqlite_backup").order_by("id")
		kinds = list(audit_events.values_list("kind", flat=True))
		self.assertEqual(kinds, ["audit-prepared", "audit-completed"])
		prepared, completed = list(audit_events)
		self.assertEqual(prepared.details["username"], self.superuser.get_username())
		self.assertEqual(prepared.details["size_bytes"], len(body))
		self.assertEqual(completed.details["bytes_streamed"], len(body))
		self.assertEqual(completed.details["size_bytes"], len(body))


class RunDueTasksCommandTestCase(SetupMixin, TestCase):
	def test_command_cleans_expired_and_locked_password_reset_codes(self):
		expired = PasswordResetCode.objects.create(user=self.regular_user, code_hash="x")
		expired.created_at = timezone.now() - timedelta(hours=2)
		expired.save(update_fields=["created_at"])
		PasswordResetCode.objects.create(
			user=self.secondary_user,
			code_hash="y",
			failed_attempts=PASSWORD_RESET_CODE_MAX_ATTEMPTS,
		)

		call_command("run_due_tasks", "--max-links", "0")

		self.assertEqual(PasswordResetCode.objects.count(), 0)
		self.assertTrue(SystemEvent.objects.filter(kind="maintenance").exists())

	def test_command_skips_when_lock_is_held(self):
		MaintenanceLock.objects.create(key="run_due_tasks", acquired_at=timezone.now())

		with patch("ops.management.commands.run_due_tasks.scrape_link") as scrape_link:
			call_command("run_due_tasks")

		scrape_link.assert_not_called()

	def test_command_does_not_release_newer_stale_lock_takeover(self):
		from ops.management.commands.run_due_tasks import _LOCK_KEY, _release_lock

		first_acquired_at = timezone.now() - timedelta(hours=2)
		second_acquired_at = timezone.now()
		MaintenanceLock.objects.create(key=_LOCK_KEY, acquired_at=second_acquired_at)

		_release_lock(first_acquired_at)

		lock = MaintenanceLock.objects.get(key=_LOCK_KEY)
		self.assertEqual(lock.acquired_at, second_acquired_at)

	def test_command_scrapes_due_links_and_sets_next_scrape(self):
		Link.objects.update(next_scrape_at=timezone.now() + timedelta(hours=1))
		link = self.regular_user.link_set.first()
		assert isinstance(link, Link)
		link.next_scrape_at = timezone.now() - timedelta(minutes=1)
		link.scrape_interval_minutes = 30
		link.save(update_fields=["next_scrape_at", "scrape_interval_minutes"])

		with patch("ops.management.commands.run_due_tasks.scrape_link", return_value=Ok(2)):
			call_command("run_due_tasks", "--max-links", "1", "--delay", "0")

		link.refresh_from_db()
		self.assertEqual(link.scrape_failure_count, 0)
		self.assertEqual(link.last_scrape_error, "")
		self.assertIsNotNone(link.next_scrape_at)
		self.assertGreater(link.next_scrape_at, timezone.now())

	def test_command_backs_off_failed_scrapes(self):
		Link.objects.update(next_scrape_at=timezone.now() + timedelta(hours=1))
		link = self.regular_user.link_set.first()
		assert isinstance(link, Link)
		link.next_scrape_at = timezone.now() - timedelta(minutes=1)
		link.scrape_interval_minutes = 5
		link.save(update_fields=["next_scrape_at", "scrape_interval_minutes"])

		with patch("ops.management.commands.run_due_tasks.scrape_link", return_value=Err("network failed")):
			call_command("run_due_tasks", "--max-links", "1", "--delay", "0")

		link.refresh_from_db()
		self.assertEqual(link.scrape_failure_count, 1)
		self.assertEqual(link.last_scrape_error, "network failed")
		self.assertIsNotNone(link.next_scrape_at)
		self.assertGreater(link.next_scrape_at, timezone.now())

	def test_command_ignores_not_due_links(self):
		Link.objects.update(next_scrape_at=timezone.now() + timedelta(hours=1))

		with patch("ops.management.commands.run_due_tasks.scrape_link") as scrape_link:
			call_command("run_due_tasks", "--delay", "0")

		scrape_link.assert_not_called()
