from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from commons.test_utils import SetupMixin, login_client
from ops.models import SystemEvent


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

		self.assertTrue(response.content.startswith(b"SQLite format 3"))
