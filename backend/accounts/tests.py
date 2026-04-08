
from django.test import TestCase  # noqa: F401
from rest_framework import status  # noqa: F401
from rest_framework.test import APIClient  # noqa: F401

from accounts.models import User
from commons.test_utils import SetupMixin, ViewSetMixin, login_client  # noqa: F401
from commons.utils import create_users, password  # noqa: F401


class UserViewSetTestCase(ViewSetMixin):
	def setUp(self):
		super().setUp(
			list_view_name = "users-list",
			detail_view_name = "users-detail",
			model = User
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
			"password": "securepassword123 securepassword123"
		}
		_ = self._test_create_object(fields=fields)

		fields = {
			"username": "newuser",
			"email": "newuser@example.com",
			"password": "securepassword123 securepassword123"
		}
		self._test_create_object(fields=fields)

	def test_update_user(self):
		self._test_update_object()

	def test_delete_user(self):
		self._test_delete_object()

	def test_regular_user_permissions(self):
		fields = {
			"username": "test_username01",
			"email": "fake@example.com",
			"name": "Ichi Nii",
			"password": "securepassword123"
		}
		update_fields = {"name": "Maria"}
		permissions = {'list': True, 'retrieve': True, 'create': True}

		self._test_permissions(
			user=self.regular_user, # type: ignore
			obj_pk=self.secondary_user.pk, # type: ignore
			fields=fields,
			update_fields=update_fields,
			permissions=permissions
		)

