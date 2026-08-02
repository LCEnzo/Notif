"""Response-conformance trial: real HTTP responses validated against openapi.json.

Deliberately ONE test. It proves the pipeline end to end — Django's live
server, real HTTP, response bytes, openapi-core validation — and exercises the
Strategy contract, which is the exact class of bug where hand-rolled parsing
and the schema drift apart silently (see docs/plan-openapi-fe-contract.md).

If the wire ever stops matching the documented schema (a serializer drops a
field, a shape changes), this test fails where unit tests and the backend
drift-check cannot see it.

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

pytestmark = [pytest.mark.e2e]


@pytest.mark.django_db(transaction=True)
@override_settings(SESSION_TOKEN_COOKIE_SECURE=False)
def test_strategies_list_conforms_to_openapi(
	live_server: Any,
	django_user_model: Any,
) -> None:
	# transaction=True is required: live_server serves from a separate thread
	# and connection, so the user must be committed for the login to see it.
	# SESSION_TOKEN_COOKIE_SECURE=False: the session cookie is Secure=True by
	# design, and Python's requests honours that strictly over plain HTTP
	# (unlike Chromium's loopback exception), so the login cookie would never
	# be sent back. The flag is read from settings at response time.
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

	response = session.get(f"{live_server.url}/api/v1/monitoring/strategies/")
	assert response.status_code == 200, response.text

	request = MockRequest(
		host_url=live_server.url,
		method="GET",
		path="/api/v1/monitoring/strategies/",
		headers=dict(response.request.headers) if response.request else {},
	)
	mock_response = MockResponse(
		data=response.content,
		status_code=response.status_code,
		headers={key: value for key, value in response.headers.items() if key.lower() == "content-type"},
	)
	# Raises OpenAPIResponseError (fails the test) if the bytes diverge from
	# the documented schema; a clean return means the wire matches.
	OPENAPI.validate_response(request, mock_response)
