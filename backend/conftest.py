"""Pytest-wide fixtures for the backend suite."""

import pytest

import monitoring.safe_fetch as safe_fetch


@pytest.fixture(autouse=True)
def _bypass_public_host_resolution_for_mocked_network(monkeypatch: pytest.MonkeyPatch) -> None:
	"""Neutralize the SSRF guard's DNS resolution for the whole suite.

	requests_mock intercepts HTTPAdapter.send, but ``PublicOnlyHTTPAdapter``
	resolves the hostname before delegating to it — and ``LinkSerializer``
	validates link URLs through the same resolver — a real DNS lookup for
	tests that never touch the network. The guard itself is unit-tested
	directly (SSRF tests restore the real resolver via ``_unpatched_resolver``),
	so bypassing it here keeps the suite hermetic without losing coverage.
	"""
	original = safe_fetch.resolve_public_host
	# Test plumbing: expose the real resolver so SSRF tests can restore it.
	setattr(safe_fetch, "_unpatched_resolver", original)  # noqa: B010 — attribute name is the stash key
	monkeypatch.setattr(safe_fetch, "resolve_public_host", lambda host: None)
