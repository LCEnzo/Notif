"""Pytest-wide fixtures for the backend suite."""

import pytest

import monitoring.safe_fetch as safe_fetch


@pytest.fixture(autouse=True)
def _bypass_public_host_resolution_for_mocked_network(
	request: pytest.FixtureRequest, monkeypatch: pytest.MonkeyPatch
) -> None:
	"""Neutralize the SSRF guard's DNS resolution for the mocked-network suite.

	``PublicOnlyHTTPAdapter`` resolves the hostname before delegating to the
	mocked transport, and ``LinkSerializer`` validates link URLs through the
	same resolver — a real DNS lookup for tests that never touch the network.
	Neutralize it so the broad suite stays hermetic.

	Tests that exercise the guard itself carry the ``real_ssrf`` marker and are
	exempted: they run against the real resolver by default, so a new guard test
	cannot silently pass against a disabled guard by forgetting to restore it.
	"""
	if request.node.get_closest_marker("real_ssrf"):
		return
	monkeypatch.setattr(safe_fetch, "resolve_public_host", lambda host: None)
