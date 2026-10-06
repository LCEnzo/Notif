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
LINKS_LIST = "/api/v1/monitoring/links/"
LINK_DETAIL = "/api/v1/monitoring/links/{id}/"
TRIGGER_SCRAPE = "/api/v1/monitoring/trigger-scrape/"
HEALTH = "/api/v1/monitoring/health/"
OPS_EVENTS = "/api/v1/ops/events/"
OPS_CADDY_LOGS = "/api/v1/ops/logs/caddy/"
OPS_SQLITE_BACKUP = "/api/v1/ops/backup/sqlite/"
STRATEGY_DETAIL = "/api/v1/monitoring/strategies/{id}/"
LOGIN = "/api/v1/auth/login/"

_HTTP_METHODS = {"get", "put", "patch", "post", "delete", "head", "options", "trace"}
_ERROR_STATUSES = {"400", "401", "403", "404"}


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
	# The view's own refusals; the parse-error alternative is pinned further down.
	assert _json_body(operation["responses"]["400"])["anyOf"][0] == _ref("ErrorMessage")
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


@pytest.mark.parametrize(
	("path", "method", "documented"),
	[
		# A safe method on a detail route: the lookup can miss; no body, no CSRF.
		(LINK_DETAIL, "get", {"401", "404"}),
		# Writes add the body's 400 and the cookie session's CSRF 403.
		(LINK_DETAIL, "patch", {"400", "401", "403", "404"}),
		(LINK_DETAIL, "delete", {"401", "403", "404"}),
		# A paginated list refuses a page past the last one.
		(LINKS_LIST, "get", {"401", "404"}),
		# Neither paginated nor parameterised, and a read passes ReadOnly.
		(USERS_LIST, "get", {"401"}),
		# Anonymous registration still refuses a dead bearer token and an
		# unsafe cookie-session write without CSRF.
		(USERS_LIST, "post", {"400", "401", "403"}),
		# Admin-only and paginated.
		(OPS_EVENTS, "get", {"401", "403", "404"}),
		# The anonymous probe: only the dead bearer token.
		(HEALTH, "get", {"401"}),
		# No authenticators: login documents its own 400 and 401 and gains nothing.
		(LOGIN, "post", {"400", "401"}),
	],
)
def test_framework_error_statuses_are_documented(
	schema: dict[str, Any], path: str, method: str, documented: set[str]
) -> None:
	assert set(schema["paths"][path][method]["responses"]) & _ERROR_STATUSES == documented


def test_framework_errors_carry_drfs_detail_body(schema: dict[str, Any]) -> None:
	responses = schema["paths"][LINK_DETAIL]["patch"]["responses"]

	for code in ("401", "403", "404"):
		assert _json_body(responses[code]) == _ref("ErrorDetail"), code
	assert _component(schema, "ErrorDetail")["required"] == ["detail"]
	# A 400 is DRF's {"detail"} or a serializer's per-field errors: described, not schema'd.
	assert "content" not in responses["400"]


def test_a_status_the_view_documents_keeps_its_wording(schema: dict[str, Any]) -> None:
	login_401 = schema["paths"][LOGIN]["post"]["responses"]["401"]

	assert login_401["description"].startswith("Invalid credentials")
	assert "content" not in login_401


@pytest.mark.parametrize(
	("path", "view_body"),
	[(CHANGE_PASSWORD, "ErrorMessage"), (TRIGGER_SCRAPE, "TriggerScrapeResponse")],
)
def test_a_view_documented_400_body_also_admits_a_parse_error(
	schema: dict[str, Any], path: str, view_body: str
) -> None:
	response_400 = schema["paths"][path]["post"]["responses"]["400"]

	assert _json_body(response_400) == {"anyOf": [_ref(view_body), _ref("ErrorDetail")]}


def test_view_specific_400s_are_documented(schema: dict[str, Any]) -> None:
	strategy_delete = schema["paths"][STRATEGY_DETAIL]["delete"]["responses"]
	caddy_logs = schema["paths"][OPS_CADDY_LOGS]["get"]
	sqlite_backup = schema["paths"][OPS_SQLITE_BACKUP]["get"]["responses"]

	assert "204" in strategy_delete
	for response in (strategy_delete["400"], caddy_logs["responses"]["400"], sqlite_backup["400"]):
		assert _json_body(response) == _ref("ErrorDetail")
	limit = next(parameter for parameter in caddy_logs["parameters"] if parameter["name"] == "limit")
	assert limit["in"] == "query"
	assert (limit["schema"]["minimum"], limit["schema"]["maximum"], limit["schema"]["default"]) == (1, 200, 50)
