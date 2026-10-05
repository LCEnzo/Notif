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


def test_user_detail_offers_patch_and_no_put(schema: dict[str, Any]) -> None:
	assert _methods(schema, USERS_DETAIL) == {"get", "patch", "delete"}


def test_get_my_info_is_get_only_and_returns_the_full_user(schema: dict[str, Any]) -> None:
	assert _methods(schema, GET_MY_INFO) == {"get"}
	assert _json_body(schema["paths"][GET_MY_INFO]["get"]["responses"]["200"]) == _ref("UserFullRead")
