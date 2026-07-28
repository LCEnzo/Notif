import json
import sqlite3
from datetime import timedelta
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

import pytest
from django.core.cache import cache
from django.core.management import call_command
from django.test import TestCase
from django.test.utils import override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework.throttling import ScopedRateThrottle

from accounts.models.password_reset import (
	PASSWORD_RESET_CODE_MAX_ATTEMPTS,
	PasswordResetCode,
)
from commons.result import Err, Ok
from commons.test_utils import SetupMixin, login_client
from monitoring.models import Link
from monitoring.rss_content_backfill import RssContentBackfillSummary
from ops.models import MaintenanceLock, SystemEvent

pytestmark = pytest.mark.timeout(30)


class OpsApiTestCase(SetupMixin, TestCase):
	def setUp(self):
		super().setUp()
		cache.clear()

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

	def test_openapi_schema_generates(self):
		response = APIClient().get(reverse("schema"))

		self.assertEqual(response.status_code, 200)
		self.assertIn("openapi", response.data)
		self.assertIn("/api/v1/client-events/", response.data["paths"])

	def test_caddy_logs_require_staff_user(self):
		client = login_client(APIClient(), self.regular_user.get_username())

		response = client.get(reverse("caddy-access-logs"))

		self.assertEqual(response.status_code, 403)

	def test_staff_can_read_caddy_logs(self):
		with TemporaryDirectory() as tmp_dir:
			log_path = f"{tmp_dir}/access.json"
			with Path(log_path).open("w", encoding="utf-8") as log_file:
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
		def fake_backup(_source, _db_name, tmp_path):
			with Path(tmp_path).open("wb") as fh:
				fh.write(b"SQLite format 3\x00" + b"\x00" * 100)

		client = login_client(APIClient(), self.superuser.get_username())

		with patch("ops.views._write_sqlite_backup", side_effect=fake_backup) as write_backup:
			response = client.get(reverse("download-sqlite-backup"))

		self.assertEqual(response.status_code, 200)
		write_backup.assert_called_once()
		self.assertEqual(response["Content-Type"], "application/vnd.sqlite3")
		self.assertIn("attachment;", response["Content-Disposition"])
		self.assertEqual(response["Cache-Control"], "no-store")
		self.assertTrue(response.streaming)
		streaming_content = getattr(response, "streaming_content", None)
		assert streaming_content is not None, "Expected streaming response"

		body = b"".join(streaming_content)
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

	def test_write_sqlite_backup_handles_memory_database(self):
		from ops.views import _write_sqlite_backup

		source = sqlite3.connect(":memory:")
		try:
			source.execute("create table example (value text)")
			source.execute("insert into example values ('ok')")
			source.commit()
			with TemporaryDirectory() as tmp_dir:
				backup_path = f"{tmp_dir}/backup.sqlite3"

				_write_sqlite_backup(source, ":memory:", backup_path)

				restored = sqlite3.connect(backup_path)
				try:
					rows = restored.execute("select value from example").fetchall()
				finally:
					restored.close()
		finally:
			source.close()

		self.assertEqual(rows, [("ok",)])

	def test_client_event_endpoint_records_scrubbed_frontend_event(self):
		response = APIClient().post(
			reverse("client-events"),
			{
				"category": "contract_violation",
				"route": "/home?token=secret",
				"endpoint": "GET /monitoring/links/",
				"contract_path": "$.results[0].id",
				"expected": "integer",
				"actual": "string",
				"message": "Bearer abc.def user@example.com notif_refresh=secret",
				"stack": "password=hunter2",
			},
			format="json",
		)

		self.assertEqual(response.status_code, 202)
		event = SystemEvent.objects.get(source="frontend")
		self.assertEqual(event.kind, "client-contract_violation")
		self.assertNotIn("abc.def", event.message)
		self.assertNotIn("user@example.com", event.message)
		self.assertNotIn("secret", event.message)
		self.assertEqual(event.details["contract_path"], "$.results[0].id")

	def test_client_event_endpoint_rejects_unknown_category(self):
		response = APIClient().post(
			reverse("client-events"),
			{"category": "bogus", "message": "bad"},
			format="json",
		)

		self.assertEqual(response.status_code, 400)
		self.assertFalse(SystemEvent.objects.filter(source="frontend").exists())

	def test_client_event_endpoint_rejects_form_encoded_posts(self):
		"""A cross-site form must not be able to write rows to this anonymous sink."""
		response = APIClient().post(
			reverse("client-events"),
			{"category": "unexpected_failure", "message": "from a hidden form"},
			format="multipart",
		)

		self.assertEqual(response.status_code, 415)
		self.assertFalse(SystemEvent.objects.filter(source="frontend").exists())

	def test_client_event_endpoint_rejects_text_plain_posts(self):
		"""text/plain is the other enctype a form can emit."""
		response = APIClient().post(
			reverse("client-events"),
			'{"category": "unexpected_failure", "message": "from a hidden form"}',
			content_type="text/plain",
		)

		self.assertEqual(response.status_code, 415)
		self.assertFalse(SystemEvent.objects.filter(source="frontend").exists())

	def test_client_event_endpoint_is_throttled(self):
		client = APIClient()
		payload = {"category": "unexpected_failure", "message": "one"}

		with patch.object(ScopedRateThrottle, "THROTTLE_RATES", {"client_events": "2/min"}):
			self.assertEqual(client.post(reverse("client-events"), payload, format="json").status_code, 202)
			self.assertEqual(client.post(reverse("client-events"), payload, format="json").status_code, 202)
			self.assertEqual(client.post(reverse("client-events"), payload, format="json").status_code, 429)


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

	def test_command_records_pending_rss_content_backfill_progress(self):
		summary = RssContentBackfillSummary(
			links_considered=1,
			links_processed=1,
			updates_checked=3,
			updates_updated=2,
			last_link_pk=42,
			completed=False,
		)

		with patch("ops.management.commands.run_due_tasks.backfill_rss_update_content", return_value=summary):
			call_command("run_due_tasks", "--max-links", "0", "--delay", "0")

		event = SystemEvent.objects.get(kind="rss-content-backfill-progress")
		self.assertEqual(event.source, "monitoring.backfill_rss_update_content")
		self.assertEqual(event.details["last_link_pk"], 42)
		self.assertEqual(event.details["updates_updated"], 2)

	def test_command_skips_rss_content_backfill_after_completion_marker(self):
		SystemEvent.objects.create(
			level=SystemEvent.Level.INFO,
			source="monitoring.backfill_rss_update_content",
			kind="rss-content-backfill-completed",
			message="RSS content backfill completed.",
		)

		with patch("ops.management.commands.run_due_tasks.backfill_rss_update_content") as backfill:
			call_command("run_due_tasks", "--max-links", "0", "--delay", "0")

		backfill.assert_not_called()


class SystemEventHandlerTestCase(TestCase):
	def test_emit_creates_system_event(self):
		import logging

		from ops.logging import SystemEventHandler

		handler = SystemEventHandler()
		record = logging.LogRecord(
			name="test.logger",
			level=logging.WARNING,
			pathname="/app/test.py",
			lineno=42,
			msg="disk running low: 92%%",
			args=(),
			exc_info=None,
		)
		handler.emit(record)

		event = SystemEvent.objects.get(kind="log")
		self.assertEqual(event.level, "warning")
		self.assertEqual(event.source, "test.logger")
		self.assertIn("disk running low", event.message)
		self.assertEqual(event.details["pathname"], "/app/test.py")
		self.assertEqual(event.details["lineno"], 42)

	def test_emit_truncates_long_source(self):
		import logging

		from ops.logging import SystemEventHandler

		handler = SystemEventHandler()
		record = logging.LogRecord(
			name="x" * 200,
			level=logging.ERROR,
			pathname="/app/test.py",
			lineno=1,
			msg="test",
			args=(),
			exc_info=None,
		)
		handler.emit(record)

		event = SystemEvent.objects.get(kind="log")
		self.assertEqual(len(event.source), 120)

	def test_emit_truncates_long_message(self):
		import logging

		from ops.logging import SystemEventHandler

		handler = SystemEventHandler()
		record = logging.LogRecord(
			name="test",
			level=logging.INFO,
			pathname="/app/test.py",
			lineno=1,
			msg="x" * 2000,
			args=(),
			exc_info=None,
		)
		handler.emit(record)

		event = SystemEvent.objects.get(kind="log")
		self.assertEqual(len(event.message), 1000)

	def test_emit_survives_db_error(self):
		import logging

		from django.db import OperationalError

		from ops.logging import SystemEventHandler

		handler = SystemEventHandler()
		record = logging.LogRecord(
			name="test",
			level=logging.WARNING,
			pathname="/app/test.py",
			lineno=1,
			msg="test",
			args=(),
			exc_info=None,
		)

		with patch("ops.models.SystemEvent.objects.create") as mock_create:
			mock_create.side_effect = OperationalError("table missing")
			# Should not raise
			handler.emit(record)

	def test_emit_survives_generic_exception(self):
		import logging

		from ops.logging import SystemEventHandler

		handler = SystemEventHandler()
		record = logging.LogRecord(
			name="test",
			level=logging.WARNING,
			pathname="/app/test.py",
			lineno=1,
			msg="test",
			args=(),
			exc_info=None,
		)

		with patch("ops.models.SystemEvent.objects.create") as mock_create:
			mock_create.side_effect = RuntimeError("something broke")
			# Should not raise — calls handleError internally
			handler.emit(record)
