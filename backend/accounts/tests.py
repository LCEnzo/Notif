from datetime import timedelta
from typing import cast
from unittest.mock import patch

from django.conf import settings
from django.db.models import Model
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient

from accounts.models import RefreshSessionFamily, RefreshTokenRecord, User
from accounts.models.password_reset import PASSWORD_RESET_CODE_MAX_ATTEMPTS, PasswordResetCode
from accounts.refresh_sessions import cleanup_refresh_sessions
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

	def test_list_does_not_leak_other_users_pii(self):
		"""Listing users must not expose email / privilege flags of other accounts."""
		response = self.api_client.get(reverse("users-list"))
		self.assertEqual(response.status_code, status.HTTP_200_OK)
		body = response.data
		items = body["results"] if isinstance(body, dict) and "results" in body else body
		self.assertGreater(len(items), 1)
		for item in items:
			self.assertNotIn("email", item)
			self.assertNotIn("is_staff", item)
			self.assertNotIn("is_superuser", item)

	def test_retrieve_other_user_does_not_leak_pii(self):
		"""Fetching another user's detail returns the minimal serializer, not their email/flags."""
		response = self.api_client.get(reverse("users-detail", kwargs={"pk": self.secondary_user.pk}))
		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertNotIn("email", response.data)
		self.assertNotIn("is_superuser", response.data)

	def test_retrieve_self_returns_full_profile(self):
		"""The requester can still see their own full profile (regression guard)."""
		response = self.api_client.get(reverse("users-detail", kwargs={"pk": self.regular_user.pk}))
		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertIn("email", response.data)

	def test_change_password_revokes_refresh_sessions(self):
		"""A password change must revoke outstanding refresh sessions so a thief is evicted."""
		# SetupMixin logged regular_user in with remember-me, creating an active family.
		family = RefreshSessionFamily.objects.filter(user=self.regular_user, revoked_at__isnull=True).first()
		assert family is not None

		response = self.api_client.post(
			reverse("users-change-password"),
			{"current_password": password, "new_password": _VALID_TEST_PASSWORD},
			format="json",
		)

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		family.refresh_from_db()
		self.assertIsNotNone(family.revoked_at)

	def test_password_reset_confirm_revokes_refresh_sessions(self):
		"""Completing a password reset must revoke outstanding refresh sessions."""
		family = RefreshSessionFamily.objects.filter(user=self.regular_user, revoked_at__isnull=True).first()
		assert family is not None
		PasswordResetCode.issue_for_user(user=self.regular_user, code="123456")

		response = self.api_client.post(
			reverse("password-reset-confirm"),
			{"email": self.regular_user.email, "code": "123456", "new_password": _VALID_TEST_PASSWORD},
			format="json",
		)

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		family.refresh_from_db()
		self.assertIsNotNone(family.revoked_at)

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

	def test_admin_password_update_for_another_user_fails_explicitly(self):
		admin_client = login_client(APIClient(), self.superuser.get_username())
		url = reverse(self.detail_view_name, kwargs={self.lookup_url_kwarg: self.regular_user.pk})

		response = admin_client.patch(url, {"password": _ALTERNATE_VALID_TEST_PASSWORD})

		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
		self.assertIn("password", response.data)
		self.regular_user.refresh_from_db()
		self.assertFalse(self.regular_user.check_password(_ALTERNATE_VALID_TEST_PASSWORD))

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
			user=self.regular_user,
			obj_pk=self.secondary_user.pk,
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
		self.assertNotIn("refresh", response.data)
		self.assertIn(settings.JWT_REFRESH_COOKIE_NAME, response.cookies)

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


class TokenCookieViewTestCase(TestCase):
	user: User

	@classmethod
	def setUpTestData(cls) -> None:
		cls.user = User.objects.create_user(
			username="remember-me-user",
			email="remember-me@example.com",
			password=_VALID_TEST_PASSWORD,
		)

	def _login(self, client: APIClient, *, remember_me: bool = True):
		return client.post(
			reverse("token_obtain_pair"),
			{
				"username": self.user.username,
				"password": _VALID_TEST_PASSWORD,
				"remember_me": remember_me,
			},
			format="json",
		)

	def test_login_sets_httponly_refresh_cookie_without_returning_refresh_token(self):
		response = self._login(APIClient())

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertIn("access", response.data)
		self.assertNotIn("refresh", response.data)
		self.assertEqual(RefreshSessionFamily.objects.count(), 1)
		self.assertEqual(RefreshTokenRecord.objects.count(), 1)

		cookie = response.cookies[settings.JWT_REFRESH_COOKIE_NAME]
		self.assertEqual(cookie["path"], settings.JWT_REFRESH_COOKIE_PATH)
		self.assertEqual(cookie["samesite"], settings.JWT_REFRESH_COOKIE_SAMESITE)
		self.assertEqual(cookie["httponly"], True)
		self.assertEqual(int(cookie["max-age"]), 72 * 60 * 60)
		self.assertEqual(response["Cache-Control"], "no-store")

	def test_login_without_remember_me_clears_existing_refresh_cookie(self):
		client = APIClient()
		client.cookies[settings.JWT_REFRESH_COOKIE_NAME] = "stale-refresh-token"

		response = self._login(client, remember_me=False)

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertIn("access", response.data)
		self.assertNotIn("refresh", response.data)
		self.assertEqual(response.cookies[settings.JWT_REFRESH_COOKIE_NAME]["max-age"], 0)
		self.assertEqual(RefreshSessionFamily.objects.count(), 0)

	def test_refresh_requires_explicit_header(self):
		client = APIClient()
		login_response = self._login(client)
		client.cookies[settings.JWT_REFRESH_COOKIE_NAME] = login_response.cookies[
			settings.JWT_REFRESH_COOKIE_NAME
		].value

		response = client.post(reverse("token_refresh"), {}, format="json")

		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
		self.assertIn("X-Refresh-Request", response.data)

	def test_refresh_uses_httponly_cookie_when_body_has_no_refresh_token(self):
		client = APIClient()
		login_response = self._login(client)
		old_cookie = login_response.cookies[settings.JWT_REFRESH_COOKIE_NAME].value
		client.cookies[settings.JWT_REFRESH_COOKIE_NAME] = old_cookie

		response = client.post(reverse("token_refresh"), {}, format="json", HTTP_X_REFRESH_REQUEST="1")

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertIn("access", response.data)
		self.assertNotIn("refresh", response.data)
		self.assertEqual(response["Cache-Control"], "no-store")
		self.assertIn(settings.JWT_REFRESH_COOKIE_NAME, response.cookies)
		self.assertNotEqual(response.cookies[settings.JWT_REFRESH_COOKIE_NAME].value, old_cookie)
		self.assertEqual(RefreshSessionFamily.objects.count(), 1)
		self.assertEqual(RefreshTokenRecord.objects.count(), 2)
		old_record = RefreshTokenRecord.objects.get(parent_jti="")
		new_record = RefreshTokenRecord.objects.exclude(parent_jti="").get()
		self.assertIsNotNone(old_record.used_at)
		self.assertEqual(new_record.parent_jti, old_record.jti)

	def test_reusing_old_refresh_token_revokes_family(self):
		client = APIClient()
		login_response = self._login(client)
		old_cookie = login_response.cookies[settings.JWT_REFRESH_COOKIE_NAME].value
		client.cookies[settings.JWT_REFRESH_COOKIE_NAME] = old_cookie
		first_refresh = client.post(reverse("token_refresh"), {}, format="json", HTTP_X_REFRESH_REQUEST="1")
		self.assertEqual(first_refresh.status_code, status.HTTP_200_OK)

		reuse_client = APIClient()
		reuse_client.cookies[settings.JWT_REFRESH_COOKIE_NAME] = old_cookie
		reuse_response = reuse_client.post(reverse("token_refresh"), {}, format="json", HTTP_X_REFRESH_REQUEST="1")

		self.assertEqual(reuse_response.status_code, status.HTTP_401_UNAUTHORIZED)
		family = RefreshSessionFamily.objects.get()
		self.assertIsNotNone(family.revoked_at)
		self.assertEqual(family.revoked_reason, RefreshSessionFamily.RevokeReason.REUSE)
		self.assertEqual(reuse_response.cookies[settings.JWT_REFRESH_COOKIE_NAME]["max-age"], 0)

	def test_logout_clears_refresh_cookie(self):
		client = APIClient()
		login_response = self._login(client)
		client.cookies[settings.JWT_REFRESH_COOKIE_NAME] = login_response.cookies[
			settings.JWT_REFRESH_COOKIE_NAME
		].value

		response = client.post(reverse("token_logout"), {}, format="json")

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertEqual(response.data, {"status": "ok"})
		self.assertEqual(response.cookies[settings.JWT_REFRESH_COOKIE_NAME]["max-age"], 0)
		self.assertEqual(response["Cache-Control"], "no-store")
		family = RefreshSessionFamily.objects.get()
		self.assertIsNotNone(family.revoked_at)
		self.assertEqual(family.revoked_reason, RefreshSessionFamily.RevokeReason.LOGOUT)

	def test_refresh_session_cleanup_deletes_expired_and_revoked_families(self):
		refresh_lifetime = cast(timedelta, settings.SIMPLE_JWT["REFRESH_TOKEN_LIFETIME"])
		active = RefreshSessionFamily.objects.create(user=self.user)
		active_old_used = RefreshTokenRecord.objects.create(
			family=active,
			jti="active-old-used",
			used_at=timezone.now() - refresh_lifetime - timedelta(minutes=1),
		)
		active_current = RefreshTokenRecord.objects.create(family=active, jti="active-current")
		expired = RefreshSessionFamily.objects.create(
			user=self.user,
			last_used_at=timezone.now() - refresh_lifetime - timedelta(minutes=1),
		)
		revoked = RefreshSessionFamily.objects.create(
			user=self.user,
			revoked_at=timezone.now() - refresh_lifetime - timedelta(minutes=1),
			revoked_reason=RefreshSessionFamily.RevokeReason.LOGOUT,
		)
		RefreshTokenRecord.objects.create(family=expired, jti="expired")
		RefreshTokenRecord.objects.create(family=revoked, jti="revoked")

		deleted = cleanup_refresh_sessions()

		self.assertEqual(deleted.families_deleted, 2)
		self.assertEqual(deleted.token_records_deleted, 1)
		self.assertTrue(RefreshSessionFamily.objects.filter(pk=active.pk).exists())
		self.assertFalse(RefreshSessionFamily.objects.filter(pk=expired.pk).exists())
		self.assertFalse(RefreshSessionFamily.objects.filter(pk=revoked.pk).exists())
		self.assertFalse(RefreshTokenRecord.objects.filter(pk=active_old_used.pk).exists())
		self.assertTrue(RefreshTokenRecord.objects.filter(pk=active_current.pk).exists())


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

		with patch("commons.email.send_password_reset_email") as mock_send:
			response = self.client.post(self.reset_url, {"email": "reset@example.com"})
		self.assertEqual(response.status_code, status.HTTP_200_OK)

		self.assertEqual(PasswordResetCode.objects.count(), 1)
		code = PasswordResetCode.objects.first()
		assert code is not None
		self.assertEqual(code.user, self.user)
		sent_code = mock_send.call_args.args[1]
		self.assertEqual(len(sent_code), 6)
		self.assertTrue(code.check_code(sent_code))
		self.assertNotEqual(code.code_hash, sent_code)
		self.assertEqual(len(code.code_hash), 64)

	def test_request_matches_email_case_insensitively(self):
		User.objects.create_user(
			username="mixedcase",
			email="MixedCase@example.com",
			password="oldpassword123!",
		)

		with patch("commons.email.send_password_reset_email") as mock_send:
			response = self.client.post(self.reset_url, {"email": "mixedcase@example.com"})

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		code = PasswordResetCode.objects.get(user__username="mixedcase")
		self.assertEqual(len(code.code_hash), 64)
		mock_send.assert_called_once()
		self.assertEqual(mock_send.call_args.args[0], "MixedCase@example.com")

	def test_request_returns_200_for_nonexistent_user(self):
		"""Reset request returns 200 even for unknown emails."""
		response = self.client.post(self.reset_url, {"email": "nobody@example.com"})
		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertEqual(PasswordResetCode.objects.count(), 0)

	def test_request_returns_200_on_send_failure(self):
		"""Reset request returns 200 even when email delivery fails - no enumeration."""
		with patch("commons.email.send_password_reset_email", side_effect=RuntimeError("SMTP down")):
			response = self.client.post(self.reset_url, {"email": "reset@example.com"})
		# Must still be 200 — a 500 would leak that the email exists.
		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertEqual(response.data, {"status": "ok"})

	def test_request_replaces_existing_code(self):
		"""New request invalidates any previous code for the same user."""
		old_code = PasswordResetCode.create_for_user(user=self.user, code="111111")

		with patch("commons.email.send_password_reset_email") as mock_send:
			response = self.client.post(self.reset_url, {"email": "reset@example.com"})
		self.assertEqual(response.status_code, status.HTTP_200_OK)

		self.assertEqual(PasswordResetCode.objects.count(), 1)
		new_code = PasswordResetCode.objects.first()
		assert new_code is not None
		self.assertNotEqual(new_code.pk, old_code.pk)
		self.assertFalse(PasswordResetCode.objects.filter(pk=old_code.pk).exists())
		self.assertTrue(new_code.check_code(mock_send.call_args.args[1]))

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
		PasswordResetCode.create_for_user(user=self.user, code="654321")

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
		code = PasswordResetCode.create_for_user(user=self.user, code="654321")

		response = self.client.post(
			self.confirm_url,
			{
				"email": "reset@example.com",
				"code": "000000",
				"new_password": "NewSecurePass123!",
			},
		)
		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
		self.assertIn("error", response.data)
		code.refresh_from_db()
		self.assertEqual(code.failed_attempts, 1)

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
		self.assertIn("error", response.data)

	def test_confirm_with_expired_code_fails(self):
		"""A code older than 30 minutes is rejected."""
		code = PasswordResetCode.create_for_user(user=self.user, code="654321")
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
		self.assertIn("error", response.data)

	def test_confirm_deletes_code_after_use(self):
		"""Successful reset deletes the code — single-use."""
		PasswordResetCode.create_for_user(user=self.user, code="654321")

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
		PasswordResetCode.create_for_user(user=self.user, code="654321")

		response = self.client.post(
			self.confirm_url,
			{
				"email": "reset@example.com",
				"code": "654321",
				"new_password": "password",  # common password
			},
		)
		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
		self.assertIn("error", response.data)

		# Password was NOT changed
		self.user.refresh_from_db()
		self.assertTrue(self.user.check_password("oldpassword123!"))

	def test_confirm_locks_code_after_too_many_failures(self):
		"""Repeated wrong guesses lock the code even if the right code arrives later."""
		code = PasswordResetCode.create_for_user(user=self.user, code="654321")

		for _ in range(PASSWORD_RESET_CODE_MAX_ATTEMPTS):
			response = self.client.post(
				self.confirm_url,
				{
					"email": "reset@example.com",
					"code": "000000",
					"new_password": "NewSecurePass123!",
				},
			)
			self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

		code.refresh_from_db()
		self.assertTrue(code.is_locked)

		response = self.client.post(
			self.confirm_url,
			{
				"email": "reset@example.com",
				"code": "654321",
				"new_password": "NewSecurePass123!",
			},
		)
		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

		self.user.refresh_from_db()
		self.assertTrue(self.user.check_password("oldpassword123!"))

	# ── __str__ hygiene ──────────────────────────────────

	def test_code_str_does_not_leak_plaintext(self):
		"""__str__ shows a hash, never the raw code."""
		code = PasswordResetCode.create_for_user(user=self.user, code="654321")
		repr_str = str(code)
		self.assertNotIn("654321", repr_str)
		self.assertIn("code_hash=", repr_str)

	def test_code_is_stored_as_keyed_hash(self):
		code = PasswordResetCode.create_for_user(user=self.user, code="654321")

		self.assertNotEqual(code.code_hash, "654321")
		self.assertTrue(code.check_code("654321"))
		self.assertFalse(code.check_code("000000"))
