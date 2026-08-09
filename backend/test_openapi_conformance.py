"""Response-conformance trial: real HTTP responses validated against openapi.json.

Deliberately ONE test. It proves the pipeline end to end — Django's live
server, real HTTP, response bytes, openapi-core validation — as a create/read
round trip driven entirely through the documented API: POST a Strategy, then
GET the list that must contain it. Both responses are validated, and the GET
is asserted non-empty so the item schema is genuinely exercised (an empty
list validates vacuously). Strategy is the exact class of bug where
hand-rolled parsing and the schema drift apart silently (see
docs/plan-openapi-fe-contract.md).

Scope, precisely: this catches documented fields dropping, changing type, or
violating their enum on the wire. It does NOT catch the backend *adding*
undocumented fields — drf-spectacular does not emit additionalProperties:
false, so extra keys validate fine. Additive drift is the codegen half's job
(the regenerated models pick the new field up, and the freshness gate forces
the regeneration into the PR).

Run with: uv run pytest -q test_openapi_conformance.py
"""

import json
from pathlib import Path
from typing import Any

import pytest
import requests
from django.test import override_settings
from openapi_core import OpenAPI
from openapi_core.testing import MockRequest, MockResponse

BACKEND_ROOT = Path(__file__).resolve().parent
OPENAPI = OpenAPI.from_dict(json.loads((BACKEND_ROOT / "openapi.json").read_text(encoding="utf-8")))

pytestmark = [pytest.mark.conformance]


def _assert_conforms(response: requests.Response, host_url: str, method: str, path: str) -> None:
	"""Validate a real HTTP response's bytes against the committed schema.

	Raises (failing the test) if the bytes diverge from what openapi.json
	documents for this operation; a clean return means the wire matches.
	"""
	request = MockRequest(
		host_url=host_url,
		method=method,
		path=path,
		headers=dict(response.request.headers) if response.request else {},
	)
	mock_response = MockResponse(
		data=response.content,
		status_code=response.status_code,
		headers={key: value for key, value in response.headers.items() if key.lower() == "content-type"},
	)
	OPENAPI.validate_response(request, mock_response)


@pytest.mark.django_db(transaction=True)
@override_settings(SESSION_TOKEN_COOKIE_SECURE=False, CSRF_COOKIE_SECURE=False)
def test_strategy_round_trip_conforms_to_openapi(
	live_server: Any,
	django_user_model: Any,
) -> None:
	# transaction=True is required: live_server serves from a separate thread
	# and connection, so the user must be committed for the login to see it.
	# The session and CSRF cookies are Secure=True in a prod-shaped test
	# configuration, and Python's requests honours that strictly over plain HTTP
	# (unlike Chromium's loopback exception), so neither would be sent back;
	# clear both flags for this live-HTTP round trip. Read from settings at
	# response time.
	username = "conformance"
	password = "conformance-pass-123"
	django_user_model.objects.create_user(
		username=username,
		password=password,
		email="conformance@example.com",
	)

	session = requests.Session()
	login = session.post(
		f"{live_server.url}/api/v1/auth/login/",
		json={"username": username, "password": password, "transport": "cookie"},
	)
	assert login.status_code == 200, login.text

	# Cookie-transport writes enforce CSRF; login hands out a readable
	# csrftoken cookie exactly so clients can echo it back in X-CSRFToken.
	created = session.post(
		f"{live_server.url}/api/v1/monitoring/strategies/",
		json={"strat_cls": "FeedStrategy", "data": {}},
		headers={"X-CSRFToken": session.cookies["csrftoken"]},
	)
	assert created.status_code == 201, created.text
	_assert_conforms(created, live_server.url, "POST", "/api/v1/monitoring/strategies/")

	listed = session.get(f"{live_server.url}/api/v1/monitoring/strategies/")
	assert listed.status_code == 200, listed.text
	# Guard against the vacuous pass: [] validates against any item schema.
	body = listed.json()
	assert body, "strategies list is empty — the item schema was never exercised"
	assert any(item.get("id") == created.json()["id"] for item in body)
	_assert_conforms(listed, live_server.url, "GET", "/api/v1/monitoring/strategies/")
