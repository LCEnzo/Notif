"""Facts about the generated OpenAPI schema that clients and the fuzzer rely on.

The schema is generated in-process from the view code, not read from
``openapi.json``, so a failure names the view that changed; the drift check
separately holds the committed file to this same output. Each test pins what
the API really does at runtime, which the view tests cover from the other side.

Run with: uv run pytest -q test_openapi_schema.py
"""

from typing import Any

import pytest
from drf_spectacular.generators import SchemaGenerator

USERS_LIST = "/api/v1/accounts/users/"
USERS_DETAIL = "/api/v1/accounts/users/{id}/"
GET_MY_INFO = "/api/v1/accounts/users/get_my_info/"
CHANGE_PASSWORD = "/api/v1/accounts/users/change_password/"
MARK_ALL_READ = "/api/v1/monitoring/notifications/mark_all_read/"

_HTTP_METHODS = {"get", "put", "patch", "post", "delete", "head", "options", "trace"}


@pytest.fixture(scope="module")
def schema() -> dict[str, Any]:
	generated: dict[str, Any] = SchemaGenerator().get_schema(request=None, public=True)
	return generated


def _methods(schema: dict[str, Any], path: str) -> set[str]:
	return set(schema["paths"][path]) & _HTTP_METHODS


def _ref(component: str) -> dict[str, str]:
	return {"$ref": f"#/components/schemas/{component}"}


def _json_body(request_or_response: dict[str, Any]) -> Any:
	return request_or_response["content"]["application/json"]["schema"]


def _component(schema: dict[str, Any], name: str) -> dict[str, Any]:
	component: dict[str, Any] = schema["components"]["schemas"][name]
	return component


def test_user_detail_offers_patch_and_no_put(schema: dict[str, Any]) -> None:
	assert _methods(schema, USERS_DETAIL) == {"get", "patch", "delete"}


def test_get_my_info_is_get_only_and_returns_the_full_user(schema: dict[str, Any]) -> None:
	assert _methods(schema, GET_MY_INFO) == {"get"}
	assert _json_body(schema["paths"][GET_MY_INFO]["get"]["responses"]["200"]) == _ref("UserFullRead")


def test_change_password_documents_its_real_body_and_answers(schema: dict[str, Any]) -> None:
	operation = schema["paths"][CHANGE_PASSWORD]["post"]

	assert _json_body(operation["requestBody"]) == _ref("ChangePasswordRequest")
	body = _component(schema, "ChangePasswordRequest")
	assert set(body["properties"]) == {"current_password", "new_password"}
	assert set(body["required"]) == {"current_password", "new_password"}
	# The view refuses an empty string for either field, as it does a missing one.
	assert {field["minLength"] for field in body["properties"].values()} == {1}

	assert _json_body(operation["responses"]["200"]) == _ref("StatusResponse")
	assert _json_body(operation["responses"]["400"]) == _ref("ErrorMessage")
	assert _component(schema, "ErrorMessage")["required"] == ["error"]


def test_mark_all_read_takes_no_body_and_returns_the_count(schema: dict[str, Any]) -> None:
	operation = schema["paths"][MARK_ALL_READ]["post"]

	assert "requestBody" not in operation
	assert _json_body(operation["responses"]["200"]) == _ref("MarkAllReadResponse")
	body = _component(schema, "MarkAllReadResponse")
	assert body["required"] == ["marked_read"]
	assert body["properties"]["marked_read"]["type"] == "integer"
	assert body["properties"]["marked_read"]["minimum"] == 0


def test_login_credentials_are_documented_as_non_blank(schema: dict[str, Any]) -> None:
	login = _component(schema, "LoginRequest")["properties"]

	assert login["username"]["minLength"] == 1
	assert login["password"]["minLength"] == 1
	# The control: device_label takes a blank string, so it carries no minimum.
	assert "minLength" not in login["device_label"]


def test_registration_is_documented_as_open_to_anonymous_callers(schema: dict[str, Any]) -> None:
	signed_in: list[dict[str, list[str]]] = [{"sessionBearer": []}, {"sessionCookie": []}]

	# A presented session is still checked (a dead bearer token is a 401), so
	# both schemes stay listed beside the anonymous alternative.
	assert schema["paths"][USERS_LIST]["post"]["security"] == [*signed_in, {}]
	# The control: listing users still needs a session.
	assert schema["paths"][USERS_LIST]["get"]["security"] == signed_in
