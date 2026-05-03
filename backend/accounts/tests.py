from django.conf import settings
from django.db.models import Model
from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APIClient

from accounts.models import User
from commons.test_utils import SetupMixin, ViewSetMixin, login_client  # noqa: F401
from commons.utils import create_users, password  # noqa: F401


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
			"password": "securepassword123 securepassword123",
		}
		_ = self._test_create_object(fields=fields)

		fields = {
			"username": "newuser",
			"email": "newuser@example.com",
			"password": "securepassword123 securepassword123",
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
			"password": "disposable123!",
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
			"password": "securepassword123",
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
