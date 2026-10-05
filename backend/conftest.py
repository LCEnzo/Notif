"""Pytest-wide fixtures for the backend suite."""

import pytest

import monitoring.safe_fetch as safe_fetch


def _resolve_nothing(host: str) -> list[str]:
	return []


@pytest.fixture(autouse=True)
def _bypass_public_host_resolution_for_mocked_network(
	request: pytest.FixtureRequest, monkeypatch: pytest.MonkeyPatch
) -> None:
	"""Keep the broad suite off real DNS and the real network.

	``LinkSerializer.validate_url`` resolves link hosts through
	``safe_fetch.resolve_public_host``: a real DNS lookup in tests that never
	touch the network. The replacement resolves every host to no addresses,
	so validation passes, and a test that reaches the guarded transport
	without a mock (``requests_mock`` replaces the adapter, so mocked tests
	never get there) fails with a ``requests.ConnectionError`` instead of
	dialling out.

	Tests that exercise the guard itself carry the ``real_ssrf`` marker and are
	exempted: they run against the real resolver by default, so a new guard test
	cannot silently pass against a disabled guard by forgetting to restore it.
	"""
	if request.node.get_closest_marker("real_ssrf"):
		return
	monkeypatch.setattr(safe_fetch, "resolve_public_host", _resolve_nothing)
