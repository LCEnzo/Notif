"""Pytest fixtures for monitoring tests."""

from collections.abc import Iterator
from unittest.mock import patch

import pytest


@pytest.fixture(autouse=True)
def _stub_ssrf_resolver() -> Iterator[None]:
	"""Strategy and scrape tests mock HTTP responses but use real public hostnames.

	Stub the SSRF guard's resolver to a fixed public address so these tests never
	perform real DNS lookups (offline-safe and fast). Tests that specifically
	exercise the guard re-patch ``commons.safe_fetch._resolve`` themselves.
	"""
	with patch("commons.safe_fetch._resolve", return_value=["93.184.216.34"]):
		yield
