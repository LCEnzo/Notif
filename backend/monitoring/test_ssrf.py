import socket
from typing import Any
from unittest.mock import patch

import pytest
import requests
import requests_mock
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from accounts.models import User
from commons import Err
from commons.test_utils import login_client
from commons.utils import password
from monitoring import safe_fetch
from monitoring.models import Strategy
from monitoring.safe_fetch import MAX_RESPONSE_BYTES, NonPublicHostError, ResponseTooLargeError
from monitoring.strategies import URL, GeneralSelectorStrategy


@pytest.mark.real_ssrf
class SSRFGuardTestCase(TestCase):
	"""The link API and the fetch layer refuse non-public targets.

	This class carries the ``real_ssrf`` marker, so conftest exempts it from the
	suite-wide resolver bypass: these tests run against the real SSRF guard by
	default, and a new guard test cannot silently pass against a disabled guard
	by forgetting to restore it. All targets below are literal addresses,
	``localhost``, or have their ``getaddrinfo`` patched, so no real DNS runs.
	"""

	def setUp(self) -> None:
		self.user = User.objects.create_user(
			username="ssrf-user",
			email="ssrf@example.com",
			password=password,
		)
		self.strategy = Strategy.objects.create(
			strat_cls="GeneralSelectorStrategy",
			data={"selectors": ["body"]},
			user=self.user,
		)
		self.client = login_client(APIClient(), "ssrf-user")

	def _create_link(self, url: str) -> Any:
		return self.client.post(
			reverse("links-list"),
			{"name": "nope", "url": url, "strategy": self.strategy.pk},
			format="json",
		)

	def test_link_api_rejects_internal_targets(self) -> None:
		for url in [
			"http://127.0.0.1/",
			"http://localhost/",
			"http://[::1]/",
			"http://10.0.0.1/",
			"http://192.168.1.1/",
			"http://172.16.0.1/",
			"http://169.254.169.254/latest/meta-data/",
			"http://2130706433/",  # decimal encoding of 127.0.0.1
		]:
			with self.subTest(url=url):
				response = self._create_link(url)
				self.assertEqual(
					response.status_code,
					400,
					msg=f"{url} -> {response.status_code} {getattr(response, 'data', None)}",
				)

	def test_link_api_accepts_public_target(self) -> None:
		with patch(
			"monitoring.safe_fetch.socket.getaddrinfo",
			return_value=[(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("93.184.216.34", 0))],
		):
			response = self._create_link("https://example.com/feed")
		self.assertEqual(response.status_code, 201)

	def test_address_classifier(self) -> None:
		for private in [
			"127.0.0.1",
			"10.0.0.1",
			"172.16.0.1",
			"192.168.1.1",
			"169.254.169.254",
			"0.0.0.0",
			"::1",
			"fe80::1",
			"fc00::1",
			"ff02::1",
		]:
			with self.subTest(address=private):
				self.assertFalse(safe_fetch._address_is_public(private))
		for public in ["8.8.8.8", "1.1.1.1", "93.184.216.34", "2606:4700::1111"]:
			with self.subTest(address=public):
				self.assertTrue(safe_fetch._address_is_public(public))
		self.assertFalse(safe_fetch._address_is_public("not-an-ip"))

	def test_resolve_public_host_rejects_mixed_records(self) -> None:
		"""A host with one public and one private record is a rebinding setup."""
		with (
			patch(
				"monitoring.safe_fetch.socket.getaddrinfo",
				return_value=[
					(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("93.184.216.34", 0)),
					(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("10.0.0.5", 0)),
				],
			),
			self.assertRaises(NonPublicHostError),
		):
			safe_fetch.resolve_public_host("rebinding.example.com")

	def test_resolve_public_host_accepts_public_records(self) -> None:
		with patch(
			"monitoring.safe_fetch.socket.getaddrinfo",
			return_value=[
				(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("93.184.216.34", 0)),
			],
		):
			safe_fetch.resolve_public_host("example.com")  # must not raise

	def test_fetch_refuses_private_address_before_any_network(self) -> None:
		with self.assertRaises(NonPublicHostError):
			safe_fetch.fetch("http://127.0.0.1/", timeout=2)

	def test_fetch_caps_response_size(self) -> None:
		with requests_mock.Mocker() as mocker:
			mocker.get("https://example.com/huge", text="x" * (MAX_RESPONSE_BYTES + 1))
			with self.assertRaises(ResponseTooLargeError):
				safe_fetch.fetch("https://example.com/huge", timeout=5)

	def test_scrape_of_internal_url_fails_closed(self) -> None:
		"""Even a link that slipped through validation cannot scrape internals."""
		strat = GeneralSelectorStrategy()
		url = URL("http://127.0.0.1/")
		result = strat(url, {"selectors": ["body"]}, {})
		assert isinstance(result, Err)

	def test_fetch_caps_redirect_bodies(self) -> None:
		"""A hostile 302 must not smuggle an unbounded body past the cap."""
		with requests_mock.Mocker() as mocker:
			mocker.get(
				"https://example.com/sneaky",
				status_code=302,
				headers={"Location": "https://example.com/final"},
				text="x" * (MAX_RESPONSE_BYTES + 1),
			)
			with self.assertRaises(ResponseTooLargeError):
				safe_fetch.fetch("https://example.com/sneaky", timeout=5)

	def test_guarded_session_pools_use_pinned_connection_classes(self) -> None:
		"""The pool manager must actually build the pinned connection classes.

		Regression: urllib3's ``PoolManager.__init__`` assigns
		``pool_classes_by_scheme`` as an *instance* attribute, so a class-level
		override is silently shadowed and stock, unpinned connections run —
		turning the DNS-pinning layer into dead code."""
		with safe_fetch.guarded_session() as session:
			for url, expected in [
				("http://example.com/", safe_fetch._PublicOnlyHTTPConnection),
				("https://example.com/", safe_fetch._PublicOnlyHTTPSConnection),
			]:
				with self.subTest(url=url):
					adapter = session.get_adapter(url)
					assert isinstance(adapter, safe_fetch.PublicOnlyHTTPAdapter)
					pool = adapter.poolmanager.connection_from_url(url)
					self.assertIs(pool.ConnectionCls, expected)

	def test_hostname_resolving_private_is_blocked_at_connect_time(self) -> None:
		"""A hostname whose DNS answer is private is refused by the pinned
		connection before any socket is opened — the rebinding / TOCTOU case
		(resolve-public at validation, resolve-private at fetch)."""
		with (
			patch("monitoring.safe_fetch.create_connection") as connect,
			patch(
				"monitoring.safe_fetch.socket.getaddrinfo",
				return_value=[(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("169.254.169.254", 0))],
			),
			self.assertRaises(NonPublicHostError),
		):
			safe_fetch.fetch("http://metadata.example.test/", timeout=2)
		connect.assert_not_called()

	def test_adapter_send_rejects_private_literal(self) -> None:
		"""The adapter refuses a private target before any connection, and that
		check runs for every hop including redirect targets."""
		adapter = safe_fetch.PublicOnlyHTTPAdapter()
		request = requests.Request("GET", "http://127.0.0.1/").prepare()
		with self.assertRaises(NonPublicHostError):
			adapter.send(request, timeout=2)

	def test_fetch_bounds_redirect_chain(self) -> None:
		"""A redirect loop cannot spin forever."""
		with requests_mock.Mocker() as mocker:
			mocker.get(
				requests_mock.ANY,
				status_code=302,
				headers={"Location": "https://example.com/loop"},
				text="",
			)
			with self.assertRaises(requests.TooManyRedirects):
				safe_fetch.fetch("https://example.com/start", timeout=5)

	def test_fetch_does_not_share_cookies_across_calls(self) -> None:
		"""A fresh session per fetch: cookies planted by one call must not ride
		along on the next call to the same host."""
		with requests_mock.Mocker() as mocker:
			mocker.get("https://example.com/sets-cookie", cookies={"sid": "attacker-controlled"})
			mocker.get("https://example.com/reads-cookie", text="ok")
			safe_fetch.fetch("https://example.com/sets-cookie", timeout=5)
			safe_fetch.fetch("https://example.com/reads-cookie", timeout=5)
			self.assertNotIn("Cookie", mocker.last_request.headers)
