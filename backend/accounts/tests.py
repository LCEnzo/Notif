from datetime import timedelta
from typing import Any
from unittest.mock import patch

from django.conf import settings
from django.core.management import call_command
from django.db.models import Model
from django.test import TestCase
from django.test.utils import override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient

from accounts.device_sessions import (
	DEAD_SESSION_RETENTION,
	MAX_LIVE_SESSIONS_PER_USER,
	TOUCH_INTERVAL,
	SessionLoginAbortedError,
	absolute_lifetime,
	cleanup_device_sessions,
	create_session,
	hash_token,
	idle_lifetime,
	live_sessions_for_user,
	session_for_token,
	touch,
)
from accounts.models import DeviceSession, User
from accounts.models.password_reset import PASSWORD_RESET_CODE_MAX_ATTEMPTS, PasswordResetCode
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


class UserSerializerSelectionTestCase(TestCase):
	"""get_serializer_class must only reveal PII (email, privilege flags) on a
	user's own row. Everyone else — including another authenticated user
	listing or fetching *other* users — gets the minimal serializer.
	"""

	user: User
	other_user: User

	@classmethod
	def setUpTestData(cls) -> None:
		cls.user = User.objects.create_user(
			username="serializer-selection-user",
			email="serializer-selection-user@example.com",
			password=_VALID_TEST_PASSWORD,
		)
		cls.other_user = User.objects.create_user(
			username="serializer-selection-other",
			email="serializer-selection-other@example.com",
			password=_ALTERNATE_VALID_TEST_PASSWORD,
		)

	def setUp(self) -> None:
		self.client_for_user = login_client(APIClient(), self.user.get_username(), _VALID_TEST_PASSWORD)

	def test_list_does_not_leak_other_users_pii(self):
		response = self.client_for_user.get(reverse("users-list"))

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		others = [row for row in response.data if row["username"] == self.other_user.username]
		self.assertEqual(len(others), 1)
		self.assertNotIn("email", others[0])
		self.assertNotIn("is_staff", others[0])
		self.assertNotIn("is_superuser", others[0])

	def test_retrieving_another_users_detail_returns_minimal_fields_only(self):
		response = self.client_for_user.get(reverse("users-detail", kwargs={"pk": self.other_user.pk}))

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertEqual(set(response.data.keys()), {"username", "date_created"})

	def test_retrieving_own_detail_returns_full_fields(self):
		response = self.client_for_user.get(reverse("users-detail", kwargs={"pk": self.user.pk}))

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertEqual(response.data["email"], self.user.email)
		self.assertIn("is_staff", response.data)
		self.assertIn("is_superuser", response.data)

	def test_get_my_info_returns_full_fields(self):
		response = self.client_for_user.get(reverse("users-get-my-info"))

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertEqual(response.data["email"], self.user.email)
		self.assertIn("is_staff", response.data)
		self.assertIn("is_superuser", response.data)


class LoginViewTestCase(TestCase):
	"""Credential exchange: transports, replacement, and the in-transaction guard."""

	user: User

	@classmethod
	def setUpTestData(cls) -> None:
		cls.user = User.objects.create_user(
			username="login-user",
			email="login-user@example.com",
			password=_VALID_TEST_PASSWORD,
		)

	def _login(self, client: APIClient | None = None, *, transport: str = "bearer", **extra: Any):
		return (client or APIClient()).post(
			reverse("auth-login"),
			{
				"username": self.user.username,
				"password": _VALID_TEST_PASSWORD,
				"transport": transport,
				**extra,
			},
			format="json",
		)

	def test_bearer_login_returns_the_token_once_and_sets_no_cookie(self):
		response = self._login(transport="bearer")

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertEqual(response.data["transport"], "bearer")
		self.assertIsNotNone(response.data["token"])
		self.assertNotIn(settings.SESSION_TOKEN_COOKIE_NAME, response.cookies)
		self.assertEqual(response["Cache-Control"], "no-store")

		session = DeviceSession.objects.get(user=self.user)
		self.assertEqual(session.transport, DeviceSession.Transport.BEARER)
		self.assertEqual(str(session.public_id), response.data["public_id"])
		# Only the hash is stored — the raw token must not be recoverable.
		self.assertEqual(session.token_hash, hash_token(response.data["token"]))
		self.assertNotEqual(session.token_hash, response.data["token"])

	def test_cookie_login_sets_an_httponly_cookie_and_returns_no_token(self):
		response = self._login(transport="cookie")

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertEqual(response.data["transport"], "cookie")
		self.assertIsNone(response.data["token"])
		self.assertEqual(response["Cache-Control"], "no-store")

		cookie = response.cookies[settings.SESSION_TOKEN_COOKIE_NAME]
		self.assertEqual(cookie["path"], settings.SESSION_TOKEN_COOKIE_PATH)
		self.assertEqual(cookie["samesite"], "Strict")
		self.assertEqual(cookie["httponly"], True)
		self.assertEqual(cookie["secure"], True)
		self.assertEqual(int(cookie["max-age"]), settings.SESSION_ABSOLUTE_LIFETIME_DAYS * 24 * 60 * 60)

		session = DeviceSession.objects.get(user=self.user)
		self.assertEqual(session.transport, DeviceSession.Transport.COOKIE)
		self.assertEqual(session.token_hash, hash_token(cookie.value))

	def test_cookie_login_emits_a_readable_csrf_cookie(self):
		"""Web writes echo the csrftoken back, so login has to hand one out."""
		response = self._login(transport="cookie")

		self.assertIn("csrftoken", response.cookies)
		self.assertTrue(response.cookies["csrftoken"].value)

	def test_login_requires_a_transport(self):
		response = APIClient().post(
			reverse("auth-login"),
			{"username": self.user.username, "password": _VALID_TEST_PASSWORD},
			format="json",
		)

		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
		self.assertIn("transport", response.data)
		self.assertEqual(DeviceSession.objects.count(), 0)

	def test_login_rejects_an_unknown_transport(self):
		response = self._login(transport="carrier-pigeon")

		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
		self.assertEqual(DeviceSession.objects.count(), 0)

	def test_wrong_password_is_401_and_creates_no_session(self):
		response = APIClient().post(
			reverse("auth-login"),
			{
				"username": self.user.username,
				# Deliberately wrong literal, not a credential.
				"password": "not-the-password",  # pragma: allowlist secret
				"transport": "bearer",
			},
			format="json",
		)

		self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
		self.assertEqual(DeviceSession.objects.count(), 0)

	def test_inactive_user_cannot_log_in(self):
		self.user.is_active = False
		self.user.save(update_fields=["is_active"])

		response = self._login()

		self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
		self.assertEqual(DeviceSession.objects.count(), 0)

	def test_device_label_is_trimmed_and_bounded(self):
		response = self._login(device_label="  " + "L" * 120 + "  ")

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		session = DeviceSession.objects.get()
		self.assertEqual(session.device_label, "L" * 120)

	def test_over_long_device_label_is_refused_rather_than_silently_cut(self):
		response = self._login(device_label="L" * 121)

		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
		self.assertIn("device_label", response.data)
		self.assertEqual(DeviceSession.objects.count(), 0)

	# ── replacement ─────────────────────────────────────────

	def test_login_replaces_the_cookie_session_it_was_handed(self):
		client = APIClient()
		first = self._login(client, transport="cookie")
		first_hash = hash_token(first.cookies[settings.SESSION_TOKEN_COOKIE_NAME].value)
		client.cookies[settings.SESSION_TOKEN_COOKIE_NAME] = first.cookies[settings.SESSION_TOKEN_COOKIE_NAME].value

		second = self._login(client, transport="cookie")

		self.assertEqual(second.status_code, status.HTTP_200_OK)
		replaced = DeviceSession.objects.get(token_hash=first_hash)
		self.assertEqual(replaced.revoke_reason, DeviceSession.RevokeReason.LOGIN_REPLACED)
		self.assertEqual(live_sessions_for_user(self.user).count(), 1)

	def test_login_replaces_the_bearer_session_it_was_handed(self):
		first = self._login(transport="bearer")
		client = APIClient()
		client.credentials(HTTP_AUTHORIZATION=f"Session {first.data['token']}")

		second = self._login(client, transport="bearer")

		self.assertEqual(second.status_code, status.HTTP_200_OK)
		replaced = DeviceSession.objects.get(token_hash=hash_token(first.data["token"]))
		self.assertEqual(replaced.revoke_reason, DeviceSession.RevokeReason.LOGIN_REPLACED)
		self.assertEqual(live_sessions_for_user(self.user).count(), 1)

	# ── in-transaction re-read ──────────────────────────────

	def _password_hash(self) -> str:
		fresh = User.objects.get(pk=self.user.pk)
		return fresh.password

	def test_login_aborts_when_the_password_changed_mid_login(self):
		"""A login validated against the old password must not outlive the change.

		The change revoked every session precisely so none survives it; committing
		this one afterwards would silently hand back what was just taken away.
		"""
		stale_hash = self._password_hash()
		self.user.set_password(_ALTERNATE_VALID_TEST_PASSWORD)
		self.user.save(update_fields=["password"])

		with self.assertRaises(SessionLoginAbortedError):
			create_session(
				user=self.user,
				transport=DeviceSession.Transport.BEARER,
				device_label="",
				ip=None,
				user_agent="",
				password_hash_at_login=stale_hash,
			)

		self.assertEqual(DeviceSession.objects.count(), 0)

	def test_login_aborts_when_the_account_was_deactivated_mid_login(self):
		current_hash = self._password_hash()
		User.objects.filter(pk=self.user.pk).update(is_active=False)

		with self.assertRaises(SessionLoginAbortedError):
			create_session(
				user=self.user,
				transport=DeviceSession.Transport.BEARER,
				device_label="",
				ip=None,
				user_agent="",
				password_hash_at_login=current_hash,
			)

		self.assertEqual(DeviceSession.objects.count(), 0)

	def test_login_aborts_when_a_reset_landed_mid_login(self):
		"""Password reset is the same write as a change, from an anonymous caller."""
		stale_hash = self._password_hash()
		PasswordResetCode.create_for_user(user=self.user, code="654321")
		confirm = APIClient().post(
			reverse("password-reset-confirm"),
			{"email": self.user.email, "code": "654321", "new_password": _ALTERNATE_VALID_TEST_PASSWORD},
			format="json",
		)
		self.assertEqual(confirm.status_code, status.HTTP_200_OK)

		with self.assertRaises(SessionLoginAbortedError):
			create_session(
				user=self.user,
				transport=DeviceSession.Transport.BEARER,
				device_label="",
				ip=None,
				user_agent="",
				password_hash_at_login=stale_hash,
			)

	def test_login_view_returns_401_when_the_session_creation_aborts(self):
		with patch("accounts.views.create_session", side_effect=SessionLoginAbortedError("changed")):
			response = self._login()

		self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
		self.assertEqual(response["Cache-Control"], "no-store")

	# ── capacity ────────────────────────────────────────────

	def test_session_cap_evicts_the_least_recently_used(self):
		for index in range(MAX_LIVE_SESSIONS_PER_USER):
			DeviceSession.objects.create(
				user=self.user,
				token_hash=f"filler-{index}",
				transport=DeviceSession.Transport.BEARER,
				last_used_at=timezone.now() - timedelta(minutes=MAX_LIVE_SESSIONS_PER_USER - index),
			)
		oldest = DeviceSession.objects.get(token_hash="filler-0")

		response = self._login()

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertEqual(live_sessions_for_user(self.user).count(), MAX_LIVE_SESSIONS_PER_USER)
		oldest.refresh_from_db()
		self.assertEqual(oldest.revoke_reason, DeviceSession.RevokeReason.CAPACITY_EVICTED)

	def test_repeated_logins_never_exceed_the_cap(self):
		"""Serialised stand-in for concurrent logins: SQLite BEGIN IMMEDIATE makes
		concurrent writers queue, so the interleaving under test is this one."""
		for _ in range(MAX_LIVE_SESSIONS_PER_USER + 5):
			self.assertEqual(self._login().status_code, status.HTTP_200_OK)

		self.assertLessEqual(live_sessions_for_user(self.user).count(), MAX_LIVE_SESSIONS_PER_USER)

	# ── cross-site request forgery gates ────────────────────

	def test_login_rejects_form_encoded_credentials(self):
		"""A cross-site top-level form POST must not be able to plant a session cookie."""
		response = APIClient().post(
			reverse("auth-login"),
			{"username": self.user.username, "password": _VALID_TEST_PASSWORD, "transport": "cookie"},
			format="multipart",
		)

		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
		self.assertNotIn(settings.SESSION_TOKEN_COOKIE_NAME, response.cookies)
		self.assertEqual(DeviceSession.objects.count(), 0)

	def test_login_rejects_text_plain_body(self):
		"""text/plain is the other enctype a form can produce — also refused."""
		response = APIClient().post(
			reverse("auth-login"),
			f'{{"username": "{self.user.username}", "password": "{_VALID_TEST_PASSWORD}", "transport": "cookie"}}',
			content_type="text/plain",
		)

		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
		self.assertNotIn(settings.SESSION_TOKEN_COOKIE_NAME, response.cookies)
		self.assertEqual(DeviceSession.objects.count(), 0)

	def test_login_expires_the_legacy_refresh_cookie(self):
		response = self._login(transport="cookie")

		legacy = response.cookies[settings.LEGACY_REFRESH_COOKIE_NAME]
		self.assertEqual(legacy["max-age"], 0)
		self.assertEqual(legacy["path"], settings.LEGACY_REFRESH_COOKIE_PATH)


class DevBootstrapLoginTestCase(TestCase):
	def test_dev_login_bootstraps_user_when_missing(self):
		self.assertFalse(User._base_manager.filter(username=settings.DEV_BOOTSTRAP_USERNAME).exists())

		response = APIClient().post(
			reverse("auth-login"),
			{
				"username": settings.DEV_BOOTSTRAP_USERNAME,
				"password": settings.DEV_BOOTSTRAP_PASSWORD,
				"transport": "bearer",
			},
			format="json",
		)

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertIsNotNone(response.data["token"])

		user = User._base_manager.get(username=settings.DEV_BOOTSTRAP_USERNAME)
		self.assertEqual(user.email, settings.DEV_BOOTSTRAP_EMAIL)
		self.assertEqual(user.name, settings.DEV_BOOTSTRAP_NAME)

	def test_wrong_password_does_not_bootstrap_dev_user(self):
		response = APIClient().post(
			reverse("auth-login"),
			{
				"username": settings.DEV_BOOTSTRAP_USERNAME,
				"password": "definitely-not-the-dev-password",
				"transport": "bearer",
			},
			format="json",
		)

		self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
		self.assertFalse(User._base_manager.filter(username=settings.DEV_BOOTSTRAP_USERNAME).exists())


class LogoutViewTestCase(TestCase):
	user: User

	@classmethod
	def setUpTestData(cls) -> None:
		cls.user = User.objects.create_user(
			username="logout-user",
			email="logout-user@example.com",
			password=_VALID_TEST_PASSWORD,
		)

	def _cookie_client(self, *, enforce_csrf: bool = False) -> tuple[APIClient, DeviceSession]:
		client = APIClient(enforce_csrf_checks=enforce_csrf)
		response = client.post(
			reverse("auth-login"),
			{"username": self.user.username, "password": _VALID_TEST_PASSWORD, "transport": "cookie"},
			format="json",
		)
		assert response.status_code == status.HTTP_200_OK
		client.cookies[settings.SESSION_TOKEN_COOKIE_NAME] = response.cookies[settings.SESSION_TOKEN_COOKIE_NAME].value
		client.cookies["csrftoken"] = response.cookies["csrftoken"].value
		return client, DeviceSession.objects.get(public_id=response.data["public_id"])

	def test_logout_revokes_the_cookie_session_and_clears_the_cookie(self):
		client, session = self._cookie_client()

		response = client.post(reverse("auth-logout"), {}, format="json")

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertEqual(response.data, {"status": "ok"})
		self.assertEqual(response["Cache-Control"], "no-store")
		self.assertEqual(response.cookies[settings.SESSION_TOKEN_COOKIE_NAME]["max-age"], 0)
		session.refresh_from_db()
		self.assertEqual(session.revoke_reason, DeviceSession.RevokeReason.LOGOUT)

	def test_logout_revokes_the_bearer_session_without_a_csrf_token(self):
		login = APIClient().post(
			reverse("auth-login"),
			{"username": self.user.username, "password": _VALID_TEST_PASSWORD, "transport": "bearer"},
			format="json",
		)
		client = APIClient(enforce_csrf_checks=True)
		client.credentials(HTTP_AUTHORIZATION=f"Session {login.data['token']}")

		response = client.post(reverse("auth-logout"), {}, format="json")

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		session = DeviceSession.objects.get(token_hash=hash_token(login.data["token"]))
		self.assertEqual(session.revoke_reason, DeviceSession.RevokeReason.LOGOUT)

	def test_logout_is_idempotent(self):
		client, session = self._cookie_client()
		first = client.post(reverse("auth-logout"), {}, format="json")
		self.assertEqual(first.status_code, status.HTTP_200_OK)
		session.refresh_from_db()
		revoked_at = session.revoked_at

		second = client.post(reverse("auth-logout"), {}, format="json")

		self.assertEqual(second.status_code, status.HTTP_200_OK)
		session.refresh_from_db()
		# The second call must not rewrite the audit trail of the first.
		self.assertEqual(session.revoked_at, revoked_at)

	def test_logout_clears_an_unknown_cookie_without_a_csrf_token(self):
		"""Clearing a dead cookie is not a protected mutation — no CSRF required."""
		client = APIClient(enforce_csrf_checks=True)
		client.cookies[settings.SESSION_TOKEN_COOKIE_NAME] = "not-a-real-token"

		response = client.post(reverse("auth-logout"), {}, format="json")

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertEqual(response.cookies[settings.SESSION_TOKEN_COOKIE_NAME]["max-age"], 0)

	def test_logout_of_a_live_cookie_session_requires_a_csrf_token(self):
		client, session = self._cookie_client(enforce_csrf=True)

		response = client.post(reverse("auth-logout"), {}, format="json")

		self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
		self.assertNotIn(settings.SESSION_TOKEN_COOKIE_NAME, response.cookies)
		session.refresh_from_db()
		self.assertIsNone(session.revoked_at)

	def test_logout_of_a_live_cookie_session_succeeds_with_a_csrf_token(self):
		client, session = self._cookie_client(enforce_csrf=True)

		response = client.post(
			reverse("auth-logout"),
			{},
			format="json",
			HTTP_X_CSRFTOKEN=client.cookies["csrftoken"].value,
		)

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		session.refresh_from_db()
		self.assertEqual(session.revoke_reason, DeviceSession.RevokeReason.LOGOUT)

	def test_logout_rejects_form_encoded_body_without_touching_cookies(self):
		"""A cross-site form POST must not be able to drop a session it never held."""
		client, session = self._cookie_client()

		response = client.post(reverse("auth-logout"), {}, format="multipart")

		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
		self.assertEqual(len(response.cookies), 0)
		session.refresh_from_db()
		self.assertIsNone(session.revoked_at)

	def test_logout_expires_the_legacy_refresh_cookie(self):
		response = APIClient().post(reverse("auth-logout"), {}, format="json")

		legacy = response.cookies[settings.LEGACY_REFRESH_COOKIE_NAME]
		self.assertEqual(legacy["max-age"], 0)
		self.assertEqual(legacy["path"], settings.LEGACY_REFRESH_COOKIE_PATH)


class SessionTokenAuthenticationTestCase(TestCase):
	"""The auth class: both transports, wrong-transport, and asymmetric rejection."""

	user: User

	@classmethod
	def setUpTestData(cls) -> None:
		cls.user = User.objects.create_user(
			username="auth-user",
			email="auth-user@example.com",
			password=_VALID_TEST_PASSWORD,
		)

	def _issue(self, transport: str) -> tuple[str, DeviceSession]:
		issued = create_session(
			user=self.user,
			transport=transport,
			device_label="",
			ip=None,
			user_agent="",
			password_hash_at_login=User.objects.get(pk=self.user.pk).password,
		)
		return issued.token, issued.session

	def test_bearer_token_authenticates(self):
		token, _ = self._issue(DeviceSession.Transport.BEARER)
		client = APIClient()
		client.credentials(HTTP_AUTHORIZATION=f"Session {token}")

		response = client.get(reverse("users-get-my-info"))

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertEqual(response.data["username"], self.user.username)

	def test_cookie_token_authenticates(self):
		token, _ = self._issue(DeviceSession.Transport.COOKIE)
		client = APIClient()
		client.cookies[settings.SESSION_TOKEN_COOKIE_NAME] = token

		response = client.get(reverse("users-get-my-info"))

		self.assertEqual(response.status_code, status.HTTP_200_OK)

	def test_cookie_token_presented_as_bearer_is_rejected(self):
		token, _ = self._issue(DeviceSession.Transport.COOKIE)
		client = APIClient()
		client.credentials(HTTP_AUTHORIZATION=f"Session {token}")

		response = client.get(reverse("users-get-my-info"))

		self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

	def test_bearer_token_presented_as_cookie_is_rejected(self):
		token, _ = self._issue(DeviceSession.Transport.BEARER)
		client = APIClient()
		client.cookies[settings.SESSION_TOKEN_COOKIE_NAME] = token

		response = client.get(reverse("users-get-my-info"))

		self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

	def test_rejection_is_401_with_the_session_challenge_not_403(self):
		"""The client tells our rejection from an edge 401 by this header alone."""
		response = APIClient().get(reverse("users-get-my-info"))

		self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
		self.assertEqual(response["WWW-Authenticate"], "Session")

	@override_settings(CORS_ALLOWED_ORIGINS=["http://localhost:5353"])
	def test_session_challenge_is_visible_to_cross_port_web_clients(self):
		response = APIClient().get(
			reverse("users-get-my-info"),
			HTTP_ORIGIN="http://localhost:5353",
		)

		exposed_headers = {header.strip().lower() for header in response["Access-Control-Expose-Headers"].split(",")}
		self.assertIn("www-authenticate", exposed_headers)

	def test_dead_cookie_on_a_protected_endpoint_is_401_with_the_challenge(self):
		token, session = self._issue(DeviceSession.Transport.COOKIE)
		session.revoke(DeviceSession.RevokeReason.REVOKED_BY_USER)
		client = APIClient()
		client.cookies[settings.SESSION_TOKEN_COOKIE_NAME] = token

		response = client.get(reverse("users-get-my-info"))

		self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
		self.assertEqual(response["WWW-Authenticate"], "Session")

	def test_dead_bearer_header_is_rejected_even_on_an_anonymous_endpoint(self):
		"""A bearer header is a deliberate per-request credential, so it raises.

		This is the asymmetry: the same dead credential presented as a cookie
		resolves as anonymous (test below), because the browser attaches cookies
		to everything whether the app meant to or not.
		"""
		token, session = self._issue(DeviceSession.Transport.BEARER)
		session.revoke(DeviceSession.RevokeReason.LOGOUT)
		client = APIClient()
		client.credentials(HTTP_AUTHORIZATION=f"Session {token}")

		response = client.post(
			reverse("client-events"), {"category": "unexpected_failure", "message": "hi"}, format="json"
		)

		self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

	def test_dead_cookie_leaves_the_anonymous_endpoints_reachable(self):
		"""The whole point of the asymmetry: outage recovery must not need a
		valid session, and a dead cookie rides along for the full absolute
		lifetime after the session died."""
		token, session = self._issue(DeviceSession.Transport.COOKIE)
		session.revoke(DeviceSession.RevokeReason.LOGOUT)

		def dead_cookie_client() -> APIClient:
			client = APIClient()
			client.cookies[settings.SESSION_TOKEN_COOKIE_NAME] = token
			return client

		with self.subTest(endpoint="health"):
			self.assertEqual(dead_cookie_client().get(reverse("health-check")).status_code, status.HTTP_200_OK)

		with self.subTest(endpoint="password reset request"):
			response = dead_cookie_client().post(
				reverse("password-reset"), {"email": "nobody@example.com"}, format="json"
			)
			self.assertEqual(response.status_code, status.HTTP_200_OK)

		with self.subTest(endpoint="password reset confirm"):
			response = dead_cookie_client().post(
				reverse("password-reset-confirm"),
				{"email": "nobody@example.com", "code": "000000", "new_password": _ALTERNATE_VALID_TEST_PASSWORD},
				format="json",
			)
			# 400 for the bad code, crucially not 401 for the dead cookie.
			self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

		with self.subTest(endpoint="registration"):
			response = dead_cookie_client().post(
				reverse("users-list"),
				{
					"username": "registered-under-a-dead-cookie",
					"email": "dead-cookie@example.com",
					"password": _ALTERNATE_VALID_TEST_PASSWORD,
				},
				format="json",
			)
			self.assertEqual(response.status_code, status.HTTP_201_CREATED)

		with self.subTest(endpoint="client events"):
			response = dead_cookie_client().post(
				reverse("client-events"), {"category": "unexpected_failure", "message": "hi"}, format="json"
			)
			self.assertEqual(response.status_code, status.HTTP_202_ACCEPTED)

	def test_inactive_user_cannot_authenticate(self):
		token, _ = self._issue(DeviceSession.Transport.BEARER)
		User.objects.filter(pk=self.user.pk).update(is_active=False)
		client = APIClient()
		client.credentials(HTTP_AUTHORIZATION=f"Session {token}")

		response = client.get(reverse("users-get-my-info"))

		self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

	def test_soft_deleting_a_user_revokes_every_session(self):
		_, first = self._issue(DeviceSession.Transport.BEARER)
		_, second = self._issue(DeviceSession.Transport.COOKIE)

		self.user.delete()

		for session in (first, second):
			session.refresh_from_db()
			self.assertEqual(session.revoke_reason, DeviceSession.RevokeReason.USER_DEACTIVATED)

	def test_direct_deactivation_revokes_every_session(self):
		_, first = self._issue(DeviceSession.Transport.BEARER)
		_, second = self._issue(DeviceSession.Transport.COOKIE)

		self.user.is_active = False
		self.user.save(update_fields=["is_active"])

		for session in (first, second):
			session.refresh_from_db()
			self.assertEqual(session.revoke_reason, DeviceSession.RevokeReason.USER_DEACTIVATED)

	def test_a_foreign_auth_scheme_is_not_treated_as_our_credential(self):
		"""A pre-cutover client's `Bearer <jwt>` is not a malformed session token."""
		client = APIClient()
		client.credentials(HTTP_AUTHORIZATION="Bearer some.jwt.value")

		response = client.get(reverse("health-check"))

		self.assertEqual(response.status_code, status.HTTP_200_OK)

	def test_malformed_session_header_is_rejected(self):
		client = APIClient()
		client.credentials(HTTP_AUTHORIZATION="Session")

		response = client.get(reverse("health-check"))

		self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

	# ── CSRF ────────────────────────────────────────────────

	def test_cookie_writes_require_a_csrf_token(self):
		token, _ = self._issue(DeviceSession.Transport.COOKIE)
		client = APIClient(enforce_csrf_checks=True)
		client.cookies[settings.SESSION_TOKEN_COOKIE_NAME] = token

		response = client.post(reverse("device-sessions-revoke-all"), {}, format="json")

		self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

	def test_cookie_reads_do_not_require_a_csrf_token(self):
		token, _ = self._issue(DeviceSession.Transport.COOKIE)
		client = APIClient(enforce_csrf_checks=True)
		client.cookies[settings.SESSION_TOKEN_COOKIE_NAME] = token

		response = client.get(reverse("device-sessions-list"))

		self.assertEqual(response.status_code, status.HTTP_200_OK)

	def test_bearer_writes_do_not_require_a_csrf_token(self):
		"""Nothing attaches a bearer header ambiently, so there is nothing to forge."""
		token, _ = self._issue(DeviceSession.Transport.BEARER)
		client = APIClient(enforce_csrf_checks=True)
		client.credentials(HTTP_AUTHORIZATION=f"Session {token}")

		response = client.post(reverse("device-sessions-revoke-all"), {}, format="json")

		self.assertEqual(response.status_code, status.HTTP_200_OK)


class SessionLifetimeTestCase(TestCase):
	user: User

	@classmethod
	def setUpTestData(cls) -> None:
		cls.user = User.objects.create_user(
			username="lifetime-user",
			email="lifetime-user@example.com",
			password=_VALID_TEST_PASSWORD,
		)

	def _session(self, **fields: Any) -> DeviceSession:
		defaults: dict[str, Any] = {
			"user": self.user,
			"token_hash": hash_token("lifetime-token"),
			"transport": DeviceSession.Transport.BEARER,
		}
		return DeviceSession.objects.create(**{**defaults, **fields})

	def test_token_hash_is_deterministic_and_not_the_token(self):
		self.assertEqual(hash_token("abc"), hash_token("abc"))
		self.assertNotEqual(hash_token("abc"), hash_token("abd"))
		self.assertEqual(len(hash_token("abc")), 64)
		self.assertNotIn("abc", hash_token("abc"))

	def test_session_just_inside_the_idle_window_is_live(self):
		self._session(last_used_at=timezone.now() - idle_lifetime() + timedelta(minutes=1))

		self.assertTrue(session_for_token("lifetime-token", transport=DeviceSession.Transport.BEARER))

	def test_session_past_the_idle_window_is_dead(self):
		self._session(last_used_at=timezone.now() - idle_lifetime() - timedelta(minutes=1))

		self.assertIsNone(session_for_token("lifetime-token", transport=DeviceSession.Transport.BEARER))

	def test_session_past_the_absolute_window_is_dead_however_recently_used(self):
		session = self._session(last_used_at=timezone.now())
		DeviceSession.objects.filter(pk=session.pk).update(
			created_at=timezone.now() - absolute_lifetime() - timedelta(minutes=1)
		)

		self.assertIsNone(session_for_token("lifetime-token", transport=DeviceSession.Transport.BEARER))

	def test_lifetimes_follow_the_configured_settings(self):
		self._session(last_used_at=timezone.now() - timedelta(days=3))

		with override_settings(SESSION_IDLE_LIFETIME_DAYS=2):
			self.assertIsNone(session_for_token("lifetime-token", transport=DeviceSession.Transport.BEARER))
		with override_settings(SESSION_IDLE_LIFETIME_DAYS=30):
			self.assertIsNotNone(session_for_token("lifetime-token", transport=DeviceSession.Transport.BEARER))

	def test_touch_advances_last_used_at_once_per_damping_interval(self):
		session = self._session(last_used_at=timezone.now() - TOUCH_INTERVAL - timedelta(minutes=1))

		touch(session)
		session.refresh_from_db()
		advanced_to = session.last_used_at

		touch(session)
		session.refresh_from_db()
		self.assertEqual(session.last_used_at, advanced_to)

	def test_concurrent_touches_write_once(self):
		"""Two requests holding stale copies of the row must not both write.

		The damping lives in the UPDATE's WHERE clause rather than in a
		read-then-write, so the second one matches zero rows.
		"""
		self._session(last_used_at=timezone.now() - TOUCH_INTERVAL - timedelta(minutes=1))
		first_view = DeviceSession.objects.get()
		second_view = DeviceSession.objects.get()

		touch(first_view)
		first_view.refresh_from_db()
		advanced_to = first_view.last_used_at

		touch(second_view)
		first_view.refresh_from_db()
		self.assertEqual(first_view.last_used_at, advanced_to)

	def test_cleanup_deletes_only_long_dead_sessions(self):
		live = self._session(token_hash="live")
		recently_revoked = self._session(
			token_hash="recently-revoked",
			revoked_at=timezone.now() - timedelta(days=1),
			revoke_reason=DeviceSession.RevokeReason.LOGOUT,
		)
		long_revoked = self._session(
			token_hash="long-revoked",
			revoked_at=timezone.now() - DEAD_SESSION_RETENTION - timedelta(minutes=1),
			revoke_reason=DeviceSession.RevokeReason.LOGOUT,
		)
		long_idle = self._session(
			token_hash="long-idle",
			last_used_at=timezone.now() - idle_lifetime() - DEAD_SESSION_RETENTION - timedelta(minutes=1),
		)

		result = cleanup_device_sessions()

		self.assertEqual(result.sessions_deleted, 2)
		self.assertTrue(DeviceSession.objects.filter(pk=live.pk).exists())
		self.assertTrue(DeviceSession.objects.filter(pk=recently_revoked.pk).exists())
		self.assertFalse(DeviceSession.objects.filter(pk=long_revoked.pk).exists())
		self.assertFalse(DeviceSession.objects.filter(pk=long_idle.pk).exists())


class DeviceSessionEndpointTestCase(TestCase):
	"""Listing and revoking the caller's own device sessions."""

	user: User
	other_user: User

	@classmethod
	def setUpTestData(cls) -> None:
		cls.user = User.objects.create_user(
			username="sessions-owner",
			email="sessions-owner@example.com",
			password=_VALID_TEST_PASSWORD,
		)
		cls.other_user = User.objects.create_user(
			username="sessions-other",
			email="sessions-other@example.com",
			password=_ALTERNATE_VALID_TEST_PASSWORD,
		)

	def setUp(self) -> None:
		self.client_for_user = login_client(APIClient(), self.user.get_username(), _VALID_TEST_PASSWORD)

	def _session(self, user: User, label: str, **fields: Any) -> DeviceSession:
		return DeviceSession.objects.create(
			user=user,
			token_hash=hash_token(f"{user.pk}-{label}"),
			transport=DeviceSession.Transport.BEARER,
			device_label=label,
			**fields,
		)

	def test_list_requires_authentication(self):
		response = APIClient().get(reverse("device-sessions-list"))

		self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

	def test_list_returns_only_the_callers_live_sessions(self):
		mine = self._session(self.user, "Pixel 8")
		self._session(self.other_user, "Other laptop")
		self._session(
			self.user,
			"Revoked laptop",
			revoked_at=timezone.now(),
			revoke_reason=DeviceSession.RevokeReason.LOGOUT,
		)

		response = self.client_for_user.get(reverse("device-sessions-list"))

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		labels = {item["device_label"] for item in response.data}
		self.assertIn("Pixel 8", labels)
		self.assertNotIn("Other laptop", labels)
		self.assertNotIn("Revoked laptop", labels)
		self.assertIn(str(mine.public_id), {item["public_id"] for item in response.data})

	def test_list_marks_the_calling_session_as_current(self):
		self._session(self.user, "Another device")

		response = self.client_for_user.get(reverse("device-sessions-list"))

		current = [item for item in response.data if item["current"]]
		self.assertEqual(len(current), 1)
		self.assertEqual(current[0]["device_label"], "")

	def test_list_excludes_sessions_past_the_absolute_lifetime(self):
		stale = self._session(self.user, "Ancient")
		DeviceSession.objects.filter(pk=stale.pk).update(
			created_at=timezone.now() - absolute_lifetime() - timedelta(minutes=1)
		)

		response = self.client_for_user.get(reverse("device-sessions-list"))

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertNotIn("Ancient", {item["device_label"] for item in response.data})

	def test_revoke_one_session(self):
		session = self._session(self.user, "Old tablet")

		response = self.client_for_user.delete(
			reverse("device-sessions-detail", kwargs={"public_id": str(session.public_id)})
		)

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertEqual(response.data, {"status": "ok", "revoked": 1})
		session.refresh_from_db()
		self.assertEqual(session.revoke_reason, DeviceSession.RevokeReason.REVOKED_BY_USER)

	def test_cannot_revoke_another_users_session(self):
		session = self._session(self.other_user, "Not yours")

		response = self.client_for_user.delete(
			reverse("device-sessions-detail", kwargs={"public_id": str(session.public_id)})
		)

		self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
		session.refresh_from_db()
		self.assertIsNone(session.revoked_at)

	def test_revoke_all_spares_the_calling_session(self):
		self._session(self.user, "Phone")
		self._session(self.user, "Laptop")
		theirs = self._session(self.other_user, "Theirs")

		response = self.client_for_user.post(reverse("device-sessions-revoke-all"), {}, format="json")

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertEqual(response.data, {"status": "ok", "revoked": 2})
		# The caller stays signed in; everything else is gone.
		self.assertEqual(live_sessions_for_user(self.user).count(), 1)
		theirs.refresh_from_db()
		self.assertIsNone(theirs.revoked_at)

	def test_revoke_all_requires_authentication(self):
		response = APIClient().post(reverse("device-sessions-revoke-all"), {}, format="json")

		self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)


class ChangePasswordTestCase(TestCase):
	user: User
	url: str

	@classmethod
	def setUpTestData(cls) -> None:
		cls.user = User.objects.create_user(
			username="change-password-user",
			email="change-password@example.com",
			password=_VALID_TEST_PASSWORD,
		)
		cls.url = reverse("users-change-password")

	def setUp(self) -> None:
		self.authed = login_client(APIClient(), self.user.get_username(), _VALID_TEST_PASSWORD)

	def _other_session(self, label: str) -> DeviceSession:
		return DeviceSession.objects.create(
			user=self.user,
			token_hash=hash_token(f"{self.user.pk}-{label}"),
			transport=DeviceSession.Transport.BEARER,
			device_label=label,
		)

	def test_requires_authentication(self):
		response = APIClient().post(
			self.url,
			{"current_password": _VALID_TEST_PASSWORD, "new_password": _ALTERNATE_VALID_TEST_PASSWORD},
			format="json",
		)

		self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

	def _bearer_client(self) -> tuple[APIClient, DeviceSession]:
		"""A client holding its own session, plus the row that session is."""
		response = APIClient().post(
			reverse("auth-login"),
			{"username": self.user.get_username(), "password": _VALID_TEST_PASSWORD, "transport": "bearer"},
			format="json",
		)
		assert response.status_code == status.HTTP_200_OK
		client = APIClient()
		client.credentials(HTTP_AUTHORIZATION=f"Session {response.data['token']}")
		session = DeviceSession.objects.get(public_id=response.data["public_id"])
		return client, session

	def test_changes_password_and_revokes_other_sessions(self):
		other_session = self._other_session("Other device")

		response = self.authed.post(
			self.url,
			{"current_password": _VALID_TEST_PASSWORD, "new_password": _ALTERNATE_VALID_TEST_PASSWORD},
			format="json",
		)

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertEqual(response.data, {"status": "ok"})
		self.user.refresh_from_db()
		self.assertTrue(self.user.check_password(_ALTERNATE_VALID_TEST_PASSWORD))
		other_session.refresh_from_db()
		self.assertEqual(other_session.revoke_reason, DeviceSession.RevokeReason.PASSWORD_CHANGE)
		# The session login_client created is the one that must survive the change.
		live = live_sessions_for_user(self.user)
		self.assertEqual(live.count(), 1)
		self.assertNotEqual(live.get().pk, other_session.pk)

	def test_change_password_keeps_the_session_that_changed_it(self):
		"""The account screen promises "you will stay logged in" - hold it to that."""
		client, own_session = self._bearer_client()
		other_session = self._other_session("Other device")

		response = client.post(
			self.url,
			{"current_password": _VALID_TEST_PASSWORD, "new_password": _ALTERNATE_VALID_TEST_PASSWORD},
			format="json",
		)

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		other_session.refresh_from_db()
		self.assertEqual(other_session.revoke_reason, DeviceSession.RevokeReason.PASSWORD_CHANGE)
		own_session.refresh_from_db()
		self.assertIsNone(own_session.revoked_at)

	def test_patch_password_is_rejected(self):
		"""A bearer token alone must never change the password: PATCH cannot verify
		the current password, so a stolen access token could take the account over."""
		client, own_session = self._bearer_client()
		other_session = self._other_session("Stolen laptop")

		response = client.patch(
			reverse("users-detail", kwargs={"pk": self.user.pk}),
			{"password": _ALTERNATE_VALID_TEST_PASSWORD},
			format="json",
		)

		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
		self.assertIn("password", response.data)
		self.user.refresh_from_db()
		self.assertTrue(self.user.check_password(_VALID_TEST_PASSWORD))
		other_session.refresh_from_db()
		self.assertIsNone(other_session.revoked_at)
		own_session.refresh_from_db()
		self.assertIsNone(own_session.revoked_at)

	def test_change_password_is_atomic_with_revocation(self):
		"""If revocation fails, the password change must roll back with it."""
		other_session = self._other_session("Other device")

		with (
			patch(
				"accounts.views.revoke_all_sessions_for_user",
				side_effect=RuntimeError("db went away"),
			),
			self.assertRaises(RuntimeError),
		):
			self.authed.post(
				self.url,
				{"current_password": _VALID_TEST_PASSWORD, "new_password": _ALTERNATE_VALID_TEST_PASSWORD},
				format="json",
			)

		self.user.refresh_from_db()
		self.assertTrue(self.user.check_password(_VALID_TEST_PASSWORD))
		other_session.refresh_from_db()
		self.assertIsNone(other_session.revoked_at)

	def test_set_password_command_revokes_all_sessions(self):
		"""Recovery assumes compromise: no session survives the command."""
		session = self._other_session("Possibly stolen")

		call_command("set_password", self.user.get_username(), "--password", _ALTERNATE_VALID_TEST_PASSWORD)

		self.user.refresh_from_db()
		self.assertTrue(self.user.check_password(_ALTERNATE_VALID_TEST_PASSWORD))
		session.refresh_from_db()
		self.assertEqual(session.revoke_reason, DeviceSession.RevokeReason.PASSWORD_CHANGE)

	def test_rejects_wrong_current_password(self):
		response = self.authed.post(
			self.url,
			{
				# Deliberately wrong literal, not a credential.
				"current_password": "not-the-current-password",  # pragma: allowlist secret
				"new_password": _ALTERNATE_VALID_TEST_PASSWORD,
			},
			format="json",
		)

		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
		self.assertIn("error", response.data)
		self.user.refresh_from_db()
		self.assertTrue(self.user.check_password(_VALID_TEST_PASSWORD))

	def test_requires_both_fields(self):
		for payload in ({"new_password": _ALTERNATE_VALID_TEST_PASSWORD}, {"current_password": _VALID_TEST_PASSWORD}):
			with self.subTest(payload=payload):
				response = self.authed.post(self.url, payload, format="json")

				self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
				self.assertIn("error", response.data)

		self.user.refresh_from_db()
		self.assertTrue(self.user.check_password(_VALID_TEST_PASSWORD))

	def test_enforces_password_validators(self):
		response = self.authed.post(
			self.url,
			{"current_password": _VALID_TEST_PASSWORD, "new_password": "password"},
			format="json",
		)

		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
		self.assertIn("error", response.data)
		self.user.refresh_from_db()
		self.assertTrue(self.user.check_password(_VALID_TEST_PASSWORD))

	def test_password_reset_confirm_also_revokes_sessions(self):
		session = self._other_session("Stolen laptop")
		PasswordResetCode.create_for_user(user=self.user, code="654321")

		response = APIClient().post(
			reverse("password-reset-confirm"),
			{
				"email": self.user.email,
				"code": "654321",
				"new_password": _ALTERNATE_VALID_TEST_PASSWORD,
			},
			format="json",
		)

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		session.refresh_from_db()
		self.assertEqual(session.revoke_reason, DeviceSession.RevokeReason.PASSWORD_CHANGE)


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
