from typing import Any

from django.http import HttpResponse
from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APIClient

from accounts.models import User
from commons.utils import create_users, password


def login_client(api_client: APIClient, username: str, password: str = password) -> APIClient:
    login_response = api_client.post(
        path=reverse("token_obtain_pair"), 
        data={"username": username, "password": password}, 
        format="json"
    )
    assert login_response.status_code == status.HTTP_200_OK

    jwt = login_response.data.get("access")
    assert jwt is not None
    
    api_client.credentials(HTTP_AUTHORIZATION=f"Bearer {jwt}")
    return api_client


class SetupMixin:
    api_client: APIClient
    regular_user: User
    secondary_user: User

    @classmethod
    def setUpTestData(cls) -> None:
        # Create users
        create_users()
        
        cls.regular_user = User.objects.first() # type: ignore
        # Tests need users to run. 
        assert (cls.regular_user is not None)

        cls.secondary_user = User.objects.exclude(pk=cls.regular_user.pk).first() # type: ignore
        assert (cls.secondary_user is not None)
        assert (cls.secondary_user.pk != cls.regular_user.pk)

        # Create and Authenticate a test client
        cls.api_client = APIClient()
        cls.api_client = login_client(cls.api_client, cls.regular_user.get_username(), password)


class ViewSetMixin(SetupMixin, TestCase):
    """
    A mixin providing common test cases for viewsets, including CRUD operations and primitive permission checks.

    To use this mixin, you should define the `list_view_name` and `detail_view_name` variables in your subclass'
    `setUp()` method. You should also set the `model` variable to be the model class that your tests are operating on.
    """
    lookup_url_kwarg = 'pk'  # The keyword argument used for object lookup in the view
    list_view_name = None  # The name of the list view, to be defined in the subclass
    detail_view_name = None  # The name of the detail view, to be defined in the subclass
    model = None  # The model class being tested, to be defined in the subclass

    def setUp(self, model) -> None:
        """
        Set up the test case by initializing the model and object under test.
        """
        self.model = model
        self.obj = self.model.objects.first()
        assert self.model is not None

    def _test_list_objects(self) -> HttpResponse:
        """
        Test that the list view returns the correct number of objects. 
        Returns the response so further testing can be done.
        """
        url = reverse(self.list_view_name)
        response = self.api_client.get(url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), self.model.objects.count()) # type: ignore

        return response

    def _test_retrieve_object(self, comparison_field: str = 'name', pk: int | None = None) -> HttpResponse:
        """
        Test that the detail view returns the correct object, using the `comparison_field`. 
        `pk` is the primary key of the object we want to retrieve. 
        Defaults to the id of the first instance returned by the model manager.
        
        Returns the response so further testing can be done.
        """
        if pk is None:
            pk = self.obj.pk
        
        url = reverse(self.detail_view_name, kwargs={self.lookup_url_kwarg: pk})
        response = self.api_client.get(url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data.get(comparison_field), self.obj.__getattribute__(comparison_field))

        return response

    def _test_create_object(self, fields: dict[str, Any] | None = None) -> HttpResponse: 
        """
        Test that objects can be created via the API. 

        Args:
            fields (dict[str, Any], optional): Specifies the data to send to the POST endpoint. 
                                            If this contains anything more than strings and lists, 
                                            you should be creating your own function instead of using this one.
                                            Defaults to `{"name": "New Instance"}`.

        Returns:
            HttpResponse: The response from the API post call.
        """
        if fields is None:
            fields = {"name": "New Instance"}

        def get_count(fields) -> int:
            """
            Helper function to get the count of objects matching the given fields.
            """
            queryset = self.model.objects.all() # type: ignore
            for field, value in fields.items():
                if type(value) == list:
                    if len(value) == 0:
                        queryset = queryset.filter(**{field: None})
                    else:
                        field_in = field + "__in"
                        queryset = queryset.filter(**{field_in: value})
                else:
                    queryset = queryset.filter(**{field: value})
            return queryset.count()

        count_before_post = get_count(fields)

        url = reverse(self.list_view_name)
        data = fields
        response = self.api_client.post(url, data)

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(get_count(fields), count_before_post + 1)

        return response

    def _test_update_object(self, field_to_update: str = 'name', new_field_value: Any = "New Instance", 
                            pk: int | None = None) -> HttpResponse:
        """
        Test that objects can be updated via the API.
        `pk` is the primary key of the object we want to retrieve. 
        Defaults to the id of the first instance returned by the model manager.
        """
        if pk is None:
            pk = self.obj.pk

        url = reverse(self.detail_view_name, kwargs={self.lookup_url_kwarg: pk})
        data = {field_to_update: new_field_value}
        response = self.api_client.patch(url, data)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.obj.refresh_from_db()
        self.assertEqual(self.obj.__getattribute__(field_to_update), new_field_value)

        return response

    def _test_delete_object(self, pk: int | None = None) -> HttpResponse:
        """
        Test that objects can be deleted via the API.
        `pk` is the primary key of the object we want to retrieve. 
        Defaults to the id of the first instance returned by the model manager.
        """
        if pk is None:
            pk = self.obj.pk

        url = reverse(self.detail_view_name, kwargs={self.lookup_url_kwarg: pk})
        response = self.api_client.delete(url)

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(self.model.objects.filter(pk=pk).exists()) # type: ignore

        return response

    def _test_permissions(self, user: User, obj_pk: int, password: str = password, 
                          fields: dict[str, Any] | None = None, update_fields: dict[str, Any] | None = None, 
                          permissions: dict[str, bool] | None = None) \
                            -> tuple[HttpResponse, ...]:
        """
        Test the permissions of the given user.
        
        This function checks whether the provided user has the appropriate permissions to perform CRUD operations
        on the object identified by `obj_pk`. The expected permissions for each operation are provided in the
        `permissions` dictionary. If an operation is not mentioned in the `permissions` dictionary, it is assumed to 
        be forbidden.

        Parameters
        ----------
        user : User
            The user whose permissions are to be tested.

        obj_pk : int
            The primary key of the object to be accessed in the test.

        password : str, optional
            The password for the user. Uses global password by default.

        fields : dict[str, Any], optional
            A dictionary of field values to be used for creating an object in the `create` test.
            The default is {"name": "New Instance"}.

        update_fields : dict[str, Any], optional
            A dictionary of field values to be used for updating an object in the `update` test.
            The default is {"name": "New Instance"}.

        permissions : dict[str, bool], optional
            A dictionary of expected permissions for the user. The dictionary should contain keys for each CRUD 
            operation, with the value being `True` if the operation is expected to be allowed, and `False` otherwise.
            The default is {'list': True, 'retrieve': True}, which means that by default the user is expected to be 
            allowed to list and retrieve objects, but not to create, update or delete them.

            The full list is `list', `retrieve`, 'create`, `update`, `delete`.

        Returns
        -------
        Returns a tuple of responses with 5 members. They originate, in order, from:
            - list endpoint
            - retrieve endpoint
            - create endpoint
            - update endpoint
            - delete endpoint

        Raises
        ------
        AssertionError
            If a CRUD operation returns a different status code than expected based on the `permissions` dictionary.
        """
        # Default args, not in the arguments since they are mutable, ugh
        if fields is None:
            fields = {"name": "New Instance"}

        if update_fields is None:
            update_fields = {"name": "New Instance"}
        
        if permissions is None:
            permissions = {'list': True, 'retrieve': True}

        # setup, responses contains the return values
        client = login_client(APIClient(), user.get_username(), password)
        self.assertTrue(self.model.objects.filter(pk=obj_pk).exists()) # type: ignore
        responses: list[HttpResponse] = []

        # get list
        url = reverse(self.list_view_name)
        response = client.get(url)
        responses.append(response)

        expected_status = status.HTTP_200_OK if permissions.get('list') else status.HTTP_403_FORBIDDEN
        self.assertEqual(response.status_code, expected_status)

        # get one object
        url = reverse(self.detail_view_name, kwargs={'pk': obj_pk})
        response = client.get(url)
        responses.append(response)

        expected_status = status.HTTP_200_OK if permissions.get('retrieve') else status.HTTP_403_FORBIDDEN
        self.assertEqual(response.status_code, expected_status)

        # create object
        url = reverse(self.list_view_name)
        data = fields
        response = client.post(url, data)
        responses.append(response)

        expected_status = status.HTTP_201_CREATED if permissions.get('create') else status.HTTP_403_FORBIDDEN
        self.assertEqual(response.status_code, expected_status)

        # update object
        url = reverse(self.detail_view_name, kwargs={'pk': obj_pk})
        data = update_fields
        response = client.patch(url, data)
        responses.append(response)

        expected_status = status.HTTP_200_OK if permissions.get('update') else status.HTTP_403_FORBIDDEN
        self.assertEqual(response.status_code, expected_status)

        # delete object
        url = reverse(self.detail_view_name, kwargs={'pk': obj_pk})
        response = client.delete(url)
        responses.append(response)

        expected_status = status.HTTP_204_NO_CONTENT if permissions.get('delete') else status.HTTP_403_FORBIDDEN
        self.assertEqual(response.status_code, expected_status)

        return tuple(responses)
