from datetime import timedelta
from unittest.mock import patch

from django.conf import settings
from django.db.models import Model
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient

from accounts.models import User
from accounts.models.password_reset import PasswordResetCode
from commons.test_utils import SetupMixin, ViewSetMixin, login_client  # noqa: F401
from commons.utils import create_users, password  # noqa: F401

_VALID_TEST_PASSWORD = "N0tif-Test-Credential-2026!"
_ALTERNATE_VALID_TEST_PASSWORD = "N0tif-Alternate-Credential-2026!"


class UserViewSetTestCase(ViewSetMixin):
	def setUp(
		self,
		list_view_name: str = "users-list",
		detail_view_name: str = "users-detail",
		model: type[Model] = User,
		obj: Model | None = None,
	) -> None:
		super().setUp(
			list_view_name=list_view_name,
			detail_view_name=detail_view_name,
			model=model,
			obj=obj or self.regular_user,
		)

	def test_list_users(self):
		self._test_list_objects()

	def test_retrieve_user(self):
		self._test_retrieve_object(comparison_field="username")

	def test_create_user(self):
		fields = {
			"username": "test_username01",
			"email": "fake@example.com",
			"name": "Ichi Nii",
			"password": _VALID_TEST_PASSWORD,
		}
		_ = self._test_create_object(fields=fields)

		fields = {
			"username": "newuser",
			"email": "newuser@example.com",
			"password": _ALTERNATE_VALID_TEST_PASSWORD,
		}
		self._test_create_object(fields=fields)

	def test_update_user(self):
		self._test_update_object()

	def test_delete_user(self):
		# Users can only delete themselves (IsRequestingThemselves permission).
		# Cannot use _test_delete_object(create_fields=...) because its DELETE
		# uses self.api_client (regular_user), and the permission requires the
		# delete to come from the user being deleted.
		create_fields = {
			"username": "disposable_delete_me",
			"email": "del@example.com",
			"name": "Delete Me",
			"password": _VALID_TEST_PASSWORD,
		}
		create_resp = self.api_client.post(reverse(self.list_view_name), create_fields)
		self.assertEqual(create_resp.status_code, status.HTTP_201_CREATED)

		disposable_client = login_client(APIClient(), create_fields["username"], create_fields["password"])
		disposable_user = User.objects.get(username=create_fields["username"])
		pk = disposable_user.pk
		url = reverse(self.detail_view_name, kwargs={self.lookup_url_kwarg: pk})
		response = disposable_client.delete(url)
		self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
		self.assertFalse(User.objects.filter(pk=pk).exists())

	def test_regular_user_permissions(self):
		fields = {
			"username": "test_username01",
			"email": "fake@example.com",
			"name": "Ichi Nii",
			"password": _VALID_TEST_PASSWORD,
		}
		update_fields = {"name": "Maria"}
		permissions = {"list": True, "retrieve": True, "create": True}

		self._test_permissions(
			user=self.regular_user,  # type: ignore
			obj_pk=self.secondary_user.pk,  # type: ignore
			fields=fields,
			update_fields=update_fields,
			permissions=permissions,
		)


class DevBootstrapTokenViewTestCase(TestCase):
	def test_dev_login_bootstraps_user_when_missing(self):
		self.assertFalse(User._base_manager.filter(username=settings.DEV_BOOTSTRAP_USERNAME).exists())

		response = APIClient().post(
			reverse("token_obtain_pair"),
			{
				"username": settings.DEV_BOOTSTRAP_USERNAME,
				"password": settings.DEV_BOOTSTRAP_PASSWORD,
			},
			format="json",
		)

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertIn("access", response.data)
		self.assertIn("refresh", response.data)

		user = User._base_manager.get(username=settings.DEV_BOOTSTRAP_USERNAME)
		self.assertEqual(user.email, settings.DEV_BOOTSTRAP_EMAIL)
		self.assertEqual(user.name, settings.DEV_BOOTSTRAP_NAME)

	def test_wrong_password_does_not_bootstrap_dev_user(self):
		response = APIClient().post(
			reverse("token_obtain_pair"),
			{
				"username": settings.DEV_BOOTSTRAP_USERNAME,
				"password": "definitely-not-the-dev-password",
			},
			format="json",
		)

		self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
		self.assertFalse(User._base_manager.filter(username=settings.DEV_BOOTSTRAP_USERNAME).exists())


class PasswordResetTestCase(TestCase):
	"""End-to-end tests for the password reset flow."""

	user: User
	client: APIClient
	reset_url: str
	confirm_url: str

	@classmethod
	def setUpTestData(cls):
		cls.user = User.objects.create_user(
			username="resetuser",
			email="reset@example.com",
			password="oldpassword123!",
		)
		cls.client = APIClient()
		cls.reset_url = reverse("password-reset")
		cls.confirm_url = reverse("password-reset-confirm")

	# ── request ────────────────────────────────────────────

	def test_request_creates_code_for_existing_user(self):
		"""Requesting a reset for an existing user creates a code."""
		self.assertEqual(PasswordResetCode.objects.count(), 0)

		response = self.client.post(self.reset_url, {"email": "reset@example.com"})
		self.assertEqual(response.status_code, status.HTTP_200_OK)

		self.assertEqual(PasswordResetCode.objects.count(), 1)
		code = PasswordResetCode.objects.first()
		assert code is not None
		self.assertEqual(code.user, self.user)
		self.assertEqual(len(code.code), 6)

	def test_request_returns_200_for_nonexistent_user(self):
		"""Reset request returns 200 even for unknown emails."""
		response = self.client.post(self.reset_url, {"email": "nobody@example.com"})
		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertEqual(PasswordResetCode.objects.count(), 0)

	def test_request_returns_200_on_send_failure(self):
		"""Reset request returns 200 even when Resend fails — no enumeration."""
		with patch("commons.email.send_password_reset_email", side_effect=RuntimeError("Resend down")):
			response = self.client.post(self.reset_url, {"email": "reset@example.com"})
		# Must still be 200 — a 500 would leak that the email exists.
		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertEqual(response.data, {"status": "ok"})  # type: ignore[union-attr]

	def test_request_replaces_existing_code(self):
		"""New request invalidates any previous code for the same user."""
		PasswordResetCode.objects.create(user=self.user, code="111111")

		response = self.client.post(self.reset_url, {"email": "reset@example.com"})
		self.assertEqual(response.status_code, status.HTTP_200_OK)

		self.assertEqual(PasswordResetCode.objects.count(), 1)
		self.assertNotEqual(PasswordResetCode.objects.first().code, "111111")  # type: ignore[union-attr]

	def test_request_sends_email_for_known_user(self):
		"""Reset request triggers email send for existing user."""
		with patch("commons.email.send_password_reset_email") as mock_send:
			response = self.client.post(self.reset_url, {"email": "reset@example.com"})
			self.assertEqual(response.status_code, status.HTTP_200_OK)
			mock_send.assert_called_once()

	def test_request_does_not_send_for_unknown_user(self):
		"""No email is sent for unknown users (no enumeration)."""
		with patch("commons.email.send_password_reset_email") as mock_send:
			response = self.client.post(self.reset_url, {"email": "nobody@example.com"})
			self.assertEqual(response.status_code, status.HTTP_200_OK)
			mock_send.assert_not_called()

	# ── confirm ──────────────────────────────────────────

	def test_confirm_with_valid_code_changes_password(self):
		"""A valid code + new password successfully resets the password."""
		PasswordResetCode.objects.create(user=self.user, code="654321")

		response = self.client.post(
			self.confirm_url,
			{
				"email": "reset@example.com",
				"code": "654321",
				"new_password": "NewSecurePass123!",
			},
		)
		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertEqual(response.data, {"status": "ok"})

		self.user.refresh_from_db()
		self.assertTrue(self.user.check_password("NewSecurePass123!"))

	def test_confirm_with_invalid_code_fails(self):
		"""Wrong code returns 400."""
		PasswordResetCode.objects.create(user=self.user, code="654321")

		response = self.client.post(
			self.confirm_url,
			{
				"email": "reset@example.com",
				"code": "000000",
				"new_password": "NewSecurePass123!",
			},
		)
		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
		self.assertIn("error", response.data)  # type: ignore[union-attr]

	def test_confirm_with_unknown_email_fails(self):
		"""Unknown email returns 400 — same message as wrong code (no enumeration)."""
		response = self.client.post(
			self.confirm_url,
			{
				"email": "nobody@example.com",
				"code": "000000",
				"new_password": "NewSecurePass123!",
			},
		)
		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
		self.assertIn("error", response.data)  # type: ignore[union-attr]

	def test_confirm_with_expired_code_fails(self):
		"""A code older than 30 minutes is rejected."""
		code = PasswordResetCode.objects.create(user=self.user, code="654321")
		# Backdate created_at past the 30-minute window
		code.created_at = timezone.now() - timedelta(minutes=31)
		code.save(update_fields=["created_at"])

		response = self.client.post(
			self.confirm_url,
			{
				"email": "reset@example.com",
				"code": "654321",
				"new_password": "NewSecurePass123!",
			},
		)
		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
		self.assertIn("error", response.data)  # type: ignore[union-attr]

	def test_confirm_deletes_code_after_use(self):
		"""Successful reset deletes the code — single-use."""
		PasswordResetCode.objects.create(user=self.user, code="654321")

		self.client.post(
			self.confirm_url,
			{
				"email": "reset@example.com",
				"code": "654321",
				"new_password": "NewSecurePass123!",
			},
		)
		self.assertEqual(PasswordResetCode.objects.count(), 0)

	def test_confirm_enforces_password_validation(self):
		"""Weak passwords are still rejected by Django validators."""
		PasswordResetCode.objects.create(user=self.user, code="654321")

		response = self.client.post(
			self.confirm_url,
			{
				"email": "reset@example.com",
				"code": "654321",
				"new_password": "password",  # common password
			},
		)
		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
		self.assertIn("error", response.data)  # type: ignore[union-attr]

		# Password was NOT changed
		self.user.refresh_from_db()
		self.assertTrue(self.user.check_password("oldpassword123!"))

	# ── __str__ hygiene ──────────────────────────────────

	def test_code_str_does_not_leak_plaintext(self):
		"""__str__ shows a hash, never the raw code."""
		code = PasswordResetCode.objects.create(user=self.user, code="654321")
		repr_str = str(code)
		self.assertNotIn("654321", repr_str)
		self.assertIn("code_hash=", repr_str)
