import socket
from typing import Any
from unittest.mock import patch

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


class SSRFGuardTestCase(TestCase):
	"""The link API and the fetch layer refuse non-public targets.

	conftest.py neutralizes the DNS resolution for the mocked-network suite;
	these tests restore the real resolver (``_unpatched_resolver``) so the
	guard itself is exercised. All targets below are literal addresses or
	``localhost``, so no real DNS is involved.
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

	def _real_resolver(self) -> Any:
		return getattr(safe_fetch, "_unpatched_resolver")  # noqa: B009 — module stash set by conftest

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
				with patch("monitoring.safe_fetch.resolve_public_host", self._real_resolver()):
					response = self._create_link(url)
				self.assertEqual(
					response.status_code,
					400,
					msg=f"{url} -> {response.status_code} {getattr(response, 'data', None)}",
				)

	def test_link_api_accepts_public_target(self) -> None:
		with patch("monitoring.safe_fetch.resolve_public_host", self._real_resolver()):
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
			patch("monitoring.safe_fetch.resolve_public_host", self._real_resolver()),
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
		with (
			patch("monitoring.safe_fetch.resolve_public_host", self._real_resolver()),
			patch(
				"monitoring.safe_fetch.socket.getaddrinfo",
				return_value=[
					(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("93.184.216.34", 0)),
				],
			),
		):
			safe_fetch.resolve_public_host("example.com")  # must not raise

	def test_fetch_refuses_private_address_before_any_network(self) -> None:
		with (
			patch("monitoring.safe_fetch.resolve_public_host", self._real_resolver()),
			self.assertRaises(NonPublicHostError),
		):
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
		with patch("monitoring.safe_fetch.resolve_public_host", self._real_resolver()):
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
