import gzip
import ipaddress
import socket
import threading
import time
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, cast
from unittest.mock import patch

import pytest
import requests
import requests_mock
from django.test import SimpleTestCase, TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from accounts.models import User
from commons import Err
from commons.test_utils import login_client
from commons.utils import password
from monitoring import safe_fetch
from monitoring.models import Strategy
from monitoring.safe_fetch import MAX_RESPONSE_BYTES, NonPublicHostError, ResponseTooLargeError
from monitoring.strategies import URL, GeneralSelectorStrategy, KemonoFavouritesStrategy, QQAlertsStrategy

# Public addresses the fake resolver hands out. Nothing ever connects to them:
# the dialer below records the address and connects to the loopback server.
_PUBLIC_A = "93.184.216.34"
_PUBLIC_B = "93.184.216.35"

# What the fake resolver answers for the loopback-transport tests.
_TEST_DNS = {
	"public.example.test": [_PUBLIC_A],
	"other.example.test": [_PUBLIC_B],
	"multi.example.test": [_PUBLIC_A, _PUBLIC_B],
	"internal.example.test": ["10.0.0.5"],
	# glibc's inet_aton reads a bare integer as an IPv4 address, as the
	# production container does; Windows' resolver would instead try DNS.
	"2130706433": ["127.0.0.1"],
}


def _no_dns(*args: object, **kwargs: object) -> None:
	raise AssertionError("unexpected DNS lookup")


_AddrInfo = tuple[socket.AddressFamily, socket.SocketKind, int, str, tuple[str, int]]


def _addrinfo(address: str, port: object) -> _AddrInfo:
	family = socket.AF_INET6 if ":" in address else socket.AF_INET
	return (family, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", (address, port if isinstance(port, int) else 0))


class _FakeResolver:
	"""Stands in for ``socket.getaddrinfo``: answers from a table, passes IP
	literals through, and fails every other name — so no test performs real DNS."""

	def __init__(self, table: dict[str, list[str]]) -> None:
		self.table = table
		self.lookups: list[str] = []

	def __call__(self, host: str, port: object, *args: object, **kwargs: object) -> list[_AddrInfo]:
		self.lookups.append(host)
		if host in self.table:
			return [_addrinfo(address, port) for address in self.table[host]]
		try:
			ipaddress.ip_address(host)
		except ValueError:
			raise socket.gaierror(socket.EAI_NONAME, f"{host!r} is not in the test resolver's table") from None
		return [_addrinfo(host, port)]


class _Dialer:
	"""Stands in for ``safe_fetch.create_connection``: records each address the
	pinned connection dials, then connects to the loopback server instead — or
	raises the configured error for that address, to model an unreachable host."""

	def __init__(self, port: int, failures: dict[str, type[OSError]] | None = None) -> None:
		self.port = port
		self.failures = failures or {}
		self.dialled: list[str] = []

	def __call__(
		self, address: tuple[str, int], timeout: object = None, *args: object, **kwargs: object
	) -> socket.socket:
		self.dialled.append(address[0])
		if address[0] in self.failures:
			raise self.failures[address[0]](f"test dialer: {address[0]} is unreachable")
		sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
		sock.settimeout(timeout if isinstance(timeout, float | int) else None)
		sock.connect(("127.0.0.1", self.port))
		return sock


_Route = Callable[[BaseHTTPRequestHandler], None]


def _respond(status: int, body: bytes = b"", headers: dict[str, str] | None = None) -> _Route:
	def route(handler: BaseHTTPRequestHandler) -> None:
		handler.send_response(status)
		for name, value in (headers or {}).items():
			handler.send_header(name, value)
		handler.send_header("Content-Length", str(len(body)))
		handler.end_headers()
		handler.wfile.write(body)

	return route


def _drip(prefix: bytes, seconds: float) -> _Route:
	"""Write ``prefix``, then a byte every 50 ms for ``seconds``: each byte well
	inside any socket timeout, the whole far past the deadline under test."""

	def route(handler: BaseHTTPRequestHandler) -> None:
		handler.wfile.write(prefix)
		stop_at = time.monotonic() + seconds
		while time.monotonic() < stop_at:
			handler.wfile.write(b"a")
			time.sleep(0.05)

	return route


class _LoopbackServer(ThreadingHTTPServer):
	"""HTTP/1.0 server on 127.0.0.1 whose responses each test sets in ``routes``."""

	def __init__(self) -> None:
		super().__init__(("127.0.0.1", 0), _Handler)
		self.routes: dict[tuple[str, str], _Route] = {}

	@property
	def port(self) -> int:
		return int(self.server_address[1])


class _Handler(BaseHTTPRequestHandler):
	def do_GET(self) -> None:
		self._dispatch()

	def do_POST(self) -> None:
		self._dispatch()

	def _dispatch(self) -> None:
		route = cast(_LoopbackServer, self.server).routes.get((self.command, self.path))
		if route is None:
			self.send_error(404)
			return
		try:
			route(self)
		except OSError:
			# The client hung up mid-response: tests that stop reading early
			# (size cap, deadline) do that on purpose.
			return

	def log_message(self, format: str, *args: Any) -> None:
		"""Keep request logging out of the test output."""


@pytest.mark.real_ssrf
class SSRFGuardTestCase(TestCase):
	"""The link API and the fetch layer refuse non-public targets.

	This class carries the ``real_ssrf`` marker, so conftest exempts it from the
	suite-wide resolver bypass: these tests run against the real SSRF guard by
	default, and a new guard test cannot silently pass against a disabled guard
	by forgetting to restore it. All targets below are literal addresses or have
	their ``getaddrinfo`` patched, so no real DNS runs.

	The ``requests_mock`` tests here replace the transport adapter (the mocker
	patches ``Session.get_adapter``), so they exercise ``fetch``'s own redirect
	and size logic only; ``RealTransportTestCase`` keeps the pinned adapter in
	the path.
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

	def test_link_api_rejects_internal_targets_without_dns(self) -> None:
		for url in [
			"http://127.0.0.1/",
			"http://localhost/",
			"http://admin.localhost:8000/",
			"http://admin.localhost./",
			"http://[::1]/",
			"http://[::ffff:127.0.0.1]/",
			"http://10.0.0.1/",
			"http://192.168.1.1/",
			"http://172.16.0.1/",
			"http://169.254.169.254/latest/meta-data/",
			# urlsplit reads the host as example.com; urllib3 would dial 127.0.0.1.
			"http://127.0.0.1\\@example.com/",
		]:
			with self.subTest(url=url), patch("monitoring.safe_fetch.socket.getaddrinfo", side_effect=_no_dns):
				response = self._create_link(url)
				self.assertEqual(
					response.status_code,
					400,
					msg=f"{url} -> {response.status_code} {getattr(response, 'data', None)}",
				)
				# Refused by validate_url, not by the URL field's own syntax check.
				self.assertIn("which is refused", str(response.data["url"]))

	def test_link_api_accepts_hostnames_without_resolving_them(self) -> None:
		"""Hostnames are left to the pinned connection at fetch time, so saving
		a link neither waits on DNS nor fails when DNS does."""
		for url in ["https://example.com/feed", "https://does-not-resolve.example.test/feed"]:
			with self.subTest(url=url), patch("monitoring.safe_fetch.socket.getaddrinfo", side_effect=_no_dns):
				response = self._create_link(url)
			self.assertEqual(response.status_code, 201)

	def test_address_classifier(self) -> None:
		for private in [
			"127.0.0.1",
			"10.0.0.1",
			"172.16.0.1",
			"192.168.1.1",
			"169.254.169.254",
			"0.0.0.0",
			"0.1.2.3",  # 0/8: Linux connects 0.x.x.x to the local host
			"100.64.0.1",  # carrier-grade NAT; note is_private is False here, only is_global catches it
			"255.255.255.255",
			"224.0.0.1",  # is_global is True for IPv4 multicast; the explicit clause refuses it
			"::1",
			"::ffff:127.0.0.1",
			"::ffff:169.254.169.254",
			"fe80::1",
			"fc00::1",
			"ff02::1",
			"64:ff9b::7f00:1",  # NAT64 of 127.0.0.1
			"64:ff9b::a9fe:a9fe",  # NAT64 of 169.254.169.254
			"::127.0.0.1",  # IPv4-compatible
			"::a00:5",  # IPv4-compatible 10.0.0.5
		]:
			with self.subTest(address=private):
				self.assertFalse(safe_fetch._address_is_public(private))
		for public in [
			"8.8.8.8",
			"1.1.1.1",
			"93.184.216.34",
			"2606:4700::1111",
			"::ffff:8.8.8.8",
			"64:ff9b::808:808",  # NAT64 of 8.8.8.8
		]:
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

	def test_resolve_public_host_returns_each_public_address_once_in_order(self) -> None:
		"""A resolver may repeat an address (an /etc/hosts duplicate, or glibc
		answering once per socket type); each address is dialled at most once."""
		with patch(
			"monitoring.safe_fetch.socket.getaddrinfo",
			return_value=[_addrinfo(address, 0) for address in [_PUBLIC_B, _PUBLIC_A, _PUBLIC_B, "2606:4700::1111"]],
		):
			addresses = safe_fetch.resolve_public_host("example.com")
		self.assertEqual(addresses, [_PUBLIC_B, _PUBLIC_A, "2606:4700::1111"])

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


class _LoopbackTransportTestCase(SimpleTestCase):
	"""Base for tests that keep the real pinned adapter, pool and sockets.

	DNS answers come from ``_FakeResolver`` and every dial is redirected by
	``_Dialer`` to a loopback server, so the guard sees the addresses a hostile
	resolver would hand it while no test leaves the machine.
	"""

	server: _LoopbackServer

	@classmethod
	def setUpClass(cls) -> None:
		super().setUpClass()
		cls.server = _LoopbackServer()
		threading.Thread(target=cls.server.serve_forever, name="ssrf-test-server", daemon=True).start()
		cls.addClassCleanup(cls.server.server_close)
		cls.addClassCleanup(cls.server.shutdown)

	def setUp(self) -> None:
		self.server.routes.clear()

	@contextmanager
	def _network(self, failures: dict[str, type[OSError]] | None = None) -> Iterator[tuple[_FakeResolver, _Dialer]]:
		resolver = _FakeResolver(_TEST_DNS)
		dialer = _Dialer(self.server.port, failures)
		with (
			patch("monitoring.safe_fetch.socket.getaddrinfo", resolver),
			patch("monitoring.safe_fetch.create_connection", dialer),
		):
			yield resolver, dialer


@pytest.mark.real_ssrf
class RealTransportTestCase(_LoopbackTransportTestCase):
	"""``fetch`` through the real pinned adapter, connection pool and sockets."""

	def test_redirect_to_non_public_target_is_refused_before_dialling(self) -> None:
		for location in ["http://internal.example.test/", "http://169.254.169.254/latest/meta-data/"]:
			self.server.routes[("GET", "/hop")] = _respond(302, headers={"Location": location})
			with self.subTest(location=location), self._network() as (_, dialer):
				with self.assertRaises(NonPublicHostError):
					safe_fetch.fetch("http://public.example.test/hop", timeout=5)
				self.assertEqual(dialer.dialled, [_PUBLIC_A])

	def test_redirects_are_followed_with_every_hop_pinned(self) -> None:
		"""Positive control for the refusal above: public hops are followed,
		each dialled at its own validated address, Host still the hostname."""
		final_hosts: list[str | None] = []

		def final(handler: BaseHTTPRequestHandler) -> None:
			final_hosts.append(handler.headers["Host"])
			_respond(200, b"final body")(handler)

		self.server.routes[("GET", "/start")] = _respond(302, headers={"Location": "/middle"})
		self.server.routes[("GET", "/middle")] = _respond(301, headers={"Location": "http://other.example.test/final"})
		self.server.routes[("GET", "/final")] = final
		with self._network() as (_, dialer):
			response = safe_fetch.fetch("http://public.example.test/start", timeout=5)
		self.assertEqual(response.content, b"final body")
		self.assertEqual(response.url, "http://other.example.test/final")
		self.assertEqual(dialer.dialled, [_PUBLIC_A, _PUBLIC_A, _PUBLIC_B])
		self.assertEqual(final_hosts, ["other.example.test"])

	def test_connection_dials_the_validated_address_not_a_fresh_lookup(self) -> None:
		"""A rebinding resolver answers public once, loopback afterwards: the
		socket must go to the address that was validated, with no second lookup."""
		lookups: list[str] = []

		def rebinding_resolver(host: str, port: object, *args: object, **kwargs: object) -> list[_AddrInfo]:
			lookups.append(host)
			return [_addrinfo(_PUBLIC_A if len(lookups) == 1 else "127.0.0.1", port)]

		dialer = _Dialer(self.server.port)
		self.server.routes[("GET", "/")] = _respond(200, b"pinned")
		with (
			patch("monitoring.safe_fetch.socket.getaddrinfo", rebinding_resolver),
			patch("monitoring.safe_fetch.create_connection", dialer),
		):
			response = safe_fetch.fetch("http://rebind.example.test/", timeout=5)
		self.assertEqual(response.content, b"pinned")
		self.assertEqual(dialer.dialled, [_PUBLIC_A])
		self.assertEqual(lookups, ["rebind.example.test"])

	def test_url_parsing_tricks_cannot_reach_loopback(self) -> None:
		for url in [
			# urlsplit reads the host as public.example.test; urllib3 dials 127.0.0.1.
			"http://127.0.0.1\\@public.example.test/",
			"http://public.example.test@127.0.0.1/",
			"http://[::ffff:127.0.0.1]/",
			# A bare integer: the stubbed resolver answers 127.0.0.1, as glibc does.
			"http://2130706433/",
		]:
			with self.subTest(url=url), self._network() as (_, dialer):
				with self.assertRaises(NonPublicHostError):
					safe_fetch.fetch(url, timeout=5)
				self.assertEqual(dialer.dialled, [])

	def test_size_cap_counts_decoded_bytes(self) -> None:
		"""Both bodies are a few hundred bytes on the wire; only counting the
		decoded bytes separates the one at the cap from the one past it."""
		cap = 64 * 1024
		for decoded_size, refused in [(cap, False), (cap + 1, True)]:
			body = gzip.compress(b"\0" * decoded_size)
			self.assertLess(len(body), cap)
			self.server.routes[("GET", "/gzip")] = _respond(200, body, {"Content-Encoding": "gzip"})
			with (
				self.subTest(decoded_size=decoded_size),
				self._network(),
				patch.object(safe_fetch, "MAX_RESPONSE_BYTES", cap),
			):
				if refused:
					with self.assertRaises(ResponseTooLargeError):
						safe_fetch.fetch("http://public.example.test/gzip", timeout=5)
				else:
					response = safe_fetch.fetch("http://public.example.test/gzip", timeout=5)
					self.assertEqual(len(response.content), decoded_size)

	def test_connect_falls_back_to_the_next_validated_address(self) -> None:
		"""As with stock urllib3, one unreachable address does not fail the
		fetch while another validated address answers."""
		self.server.routes[("GET", "/")] = _respond(200, b"second address")
		with self._network(failures={_PUBLIC_A: ConnectionRefusedError}) as (_, dialer):
			response = safe_fetch.fetch("http://multi.example.test/", timeout=5)
		self.assertEqual(response.content, b"second address")
		self.assertEqual(dialer.dialled, [_PUBLIC_A, _PUBLIC_B])

	def test_connect_failures_keep_their_requests_exception_types(self) -> None:
		"""A dial that times out surfaces as ConnectTimeout and a refused one
		as a failed new connection, over http and https alike — not as a read
		timeout or an "aborted" connection, which misdirect diagnosis."""
		for scheme in ["http", "https"]:
			with (
				self.subTest(scheme=scheme, dial="times out"),
				self._network(failures={_PUBLIC_A: TimeoutError}),
				self.assertRaises(requests.ConnectTimeout),
			):
				safe_fetch.fetch(f"{scheme}://public.example.test/", timeout=5)
			with (
				self.subTest(scheme=scheme, dial="refused"),
				self._network(failures={_PUBLIC_A: ConnectionRefusedError}),
			):
				with self.assertRaises(requests.ConnectionError) as refused:
					safe_fetch.fetch(f"{scheme}://public.example.test/", timeout=5)
				self.assertNotIsInstance(refused.exception, requests.Timeout)
				self.assertIn("Failed to establish a new connection", str(refused.exception))


@pytest.mark.real_ssrf
class GuardedLoginFlowTestCase(_LoopbackTransportTestCase):
	"""``request_capped`` and the QQ/Kemono login flows that use it."""

	def test_request_capped_stops_reading_at_the_cap(self) -> None:
		"""The body is streamed and the connection dropped past the cap — not
		read whole by requests and measured afterwards."""
		limit = 64 * 1024 * 1024
		sent = [0]
		finished = threading.Event()

		def endless(handler: BaseHTTPRequestHandler) -> None:
			handler.send_response(200)
			handler.end_headers()  # no Content-Length: the body runs until the server stops
			chunk = b"x" * 64 * 1024
			try:
				while sent[0] < limit:
					handler.wfile.write(chunk)
					sent[0] += len(chunk)
			finally:
				finished.set()

		self.server.routes[("GET", "/endless")] = endless
		with (
			self._network(),
			patch.object(safe_fetch, "MAX_RESPONSE_BYTES", 64 * 1024),
			safe_fetch.guarded_session() as session,
			self.assertRaises(ResponseTooLargeError),
		):
			safe_fetch.request_capped(
				session, "GET", "http://public.example.test/endless", timeout=5, allow_redirects=False
			)
		self.assertTrue(finished.wait(10))
		# What the server got out before the hang-up: the cap plus socket buffers.
		self.assertLess(sent[0], limit // 2)

	def test_qq_flow_logs_in_with_the_session_cookie(self) -> None:
		login: dict[str, str] = {}

		def login_route(handler: BaseHTTPRequestHandler) -> None:
			login["cookie"] = handler.headers.get("Cookie", "")
			login["form"] = handler.rfile.read(int(handler.headers["Content-Length"])).decode()
			_respond(200, b"<html>alerts</html>")(handler)

		self.server.routes[("GET", "/account/alerts")] = _respond(
			200, b"<html>log in</html>", {"Set-Cookie": "xf_session=s3ss10n; Path=/"}
		)
		self.server.routes[("POST", "/login/login")] = login_route
		with (
			self._network() as (_, dialer),
			patch.object(QQAlertsStrategy, "alerts_url", "http://public.example.test/account/alerts"),
			patch.object(QQAlertsStrategy, "login_url", "http://public.example.test/login/login"),
		):
			response = QQAlertsStrategy._get_alerts_html("reader", "pw")
		self.assertEqual(response.text, "<html>alerts</html>")
		self.assertIn("xf_session=s3ss10n", login["cookie"])
		self.assertIn("login=reader", login["form"])
		self.assertEqual(set(dialer.dialled), {_PUBLIC_A})

	def test_kemono_flow_reads_favourites_with_the_login_cookie(self) -> None:
		cookies: list[str] = []

		def favourites_route(handler: BaseHTTPRequestHandler) -> None:
			cookies.append(handler.headers.get("Cookie", ""))
			_respond(200, b"<html>favourites</html>")(handler)

		self.server.routes[("POST", "/account/login")] = _respond(200, b"ok", {"Set-Cookie": "session=k3m0n0; Path=/"})
		self.server.routes[("GET", "/favorites")] = favourites_route
		with (
			self._network(),
			patch.object(KemonoFavouritesStrategy, "login_url", "http://public.example.test/account/login"),
			patch.object(KemonoFavouritesStrategy, "fav_url", "http://public.example.test/favorites"),
		):
			response = KemonoFavouritesStrategy._get_favourites_html("reader", "pw")
		self.assertEqual(response.text, "<html>favourites</html>")
		self.assertEqual(cookies, ["session=k3m0n0"])

	def test_kemono_login_does_not_resend_credentials_on_redirect(self) -> None:
		"""requests replays a POST body on a 307/308, even to another host; the
		login stops at the redirect and keeps the cookie it set."""
		replayed: list[str] = []
		cookies: list[str] = []

		def collect(handler: BaseHTTPRequestHandler) -> None:
			replayed.append(handler.rfile.read(int(handler.headers["Content-Length"])).decode())
			_respond(200, b"thanks")(handler)

		def favourites_route(handler: BaseHTTPRequestHandler) -> None:
			cookies.append(handler.headers.get("Cookie", ""))
			_respond(200, b"<html>favourites</html>")(handler)

		self.server.routes[("POST", "/account/login")] = _respond(
			307, headers={"Location": "http://other.example.test/collect", "Set-Cookie": "session=k3m0n0; Path=/"}
		)
		self.server.routes[("POST", "/collect")] = collect
		self.server.routes[("GET", "/favorites")] = favourites_route
		with (
			self._network(),
			patch.object(KemonoFavouritesStrategy, "login_url", "http://public.example.test/account/login"),
			patch.object(KemonoFavouritesStrategy, "fav_url", "http://public.example.test/favorites"),
		):
			response = KemonoFavouritesStrategy._get_favourites_html("reader", "pw")
		self.assertEqual(replayed, [])
		self.assertEqual(cookies, ["session=k3m0n0"])
		self.assertEqual(response.text, "<html>favourites</html>")

	def test_oversized_login_flow_responses_are_refused(self) -> None:
		cap = 1024
		oversized = _respond(200, b"x" * (cap + 1))
		self.server.routes[("GET", "/account/alerts")] = _respond(200, b"log in")
		self.server.routes[("POST", "/login/login")] = oversized
		self.server.routes[("POST", "/account/login")] = _respond(200, b"ok")
		self.server.routes[("GET", "/favorites")] = oversized
		with (
			self._network(),
			patch.object(safe_fetch, "MAX_RESPONSE_BYTES", cap),
			patch.object(QQAlertsStrategy, "alerts_url", "http://public.example.test/account/alerts"),
			patch.object(QQAlertsStrategy, "login_url", "http://public.example.test/login/login"),
			patch.object(KemonoFavouritesStrategy, "login_url", "http://public.example.test/account/login"),
			patch.object(KemonoFavouritesStrategy, "fav_url", "http://public.example.test/favorites"),
		):
			with self.subTest(flow="QQ"), self.assertRaises(ResponseTooLargeError):
				QQAlertsStrategy._get_alerts_html("reader", "pw")
			with self.subTest(flow="Kemono"), self.assertRaises(ResponseTooLargeError):
				KemonoFavouritesStrategy._get_favourites_html("reader", "pw")


@pytest.mark.real_ssrf
class FetchDeadlineTestCase(_LoopbackTransportTestCase):
	"""``FETCH_DEADLINE_SECONDS`` bounds a whole fetch, not each socket call.

	Each test patches the deadline to 0.5 s against a per-call timeout of
	2-5 s and a server that stalls for 5 s, so only the deadline can end the
	fetch in under 2 s."""

	def test_deadline_cuts_off_a_header_drip_on_a_later_hop(self) -> None:
		self.server.routes[("GET", "/start")] = _respond(302, headers={"Location": "/drip"})
		self.server.routes[("GET", "/drip")] = _drip(b"HTTP/1.0 200 OK\r\nX-Drip: ", seconds=5)
		started = time.monotonic()
		with (
			self._network(),
			patch.object(safe_fetch, "FETCH_DEADLINE_SECONDS", 0.5),
			self.assertRaises(safe_fetch.DeadlineExceededError),
		):
			safe_fetch.fetch("http://public.example.test/start", timeout=2)
		self.assertLess(time.monotonic() - started, 2)

	def test_deadline_cuts_off_a_body_drip(self) -> None:
		"""Without a Content-Length the body ends at connection close. On Linux
		the shut-down socket then reads as a clean end of body (Windows reports
		an aborted connection instead), and only the session's final deadline
		check stops the truncated body being returned as the whole page."""
		self.server.routes[("GET", "/drip")] = _drip(b"HTTP/1.0 200 OK\r\n\r\n", seconds=5)
		started = time.monotonic()
		with (
			self._network(),
			patch.object(safe_fetch, "FETCH_DEADLINE_SECONDS", 0.5),
			self.assertRaises(safe_fetch.DeadlineExceededError),
		):
			safe_fetch.fetch("http://public.example.test/drip", timeout=2)
		self.assertLess(time.monotonic() - started, 2)

	def test_session_past_its_deadline_fails_even_when_nothing_raised(self) -> None:
		"""The clean-end-of-body case on any platform: no request failed inside
		the session, but it ran past the deadline, so its results are refused."""
		with (
			patch.object(safe_fetch, "FETCH_DEADLINE_SECONDS", 0.1),
			self.assertRaises(safe_fetch.DeadlineExceededError),
			safe_fetch.guarded_session(),
		):
			time.sleep(0.3)

	def test_deadline_clips_connect_attempts(self) -> None:
		"""A dial that hangs gets only the remaining budget, and no further
		address is tried once the deadline has passed."""
		dialled: list[str] = []
		timeouts: list[float] = []

		def hanging_dial(address: tuple[str, int], timeout: float, *args: object, **kwargs: object) -> socket.socket:
			dialled.append(address[0])
			timeouts.append(timeout)
			time.sleep(timeout)
			raise TimeoutError("test dialer: no answer")

		started = time.monotonic()
		with (
			patch("monitoring.safe_fetch.socket.getaddrinfo", _FakeResolver(_TEST_DNS)),
			patch("monitoring.safe_fetch.create_connection", hanging_dial),
			patch.object(safe_fetch, "FETCH_DEADLINE_SECONDS", 0.5),
			self.assertRaises(safe_fetch.DeadlineExceededError),
		):
			safe_fetch.fetch("http://multi.example.test/", timeout=5)
		self.assertLess(time.monotonic() - started, 2)
		self.assertEqual(dialled, [_PUBLIC_A])
		self.assertLessEqual(timeouts[0], 0.5)


class ResolverBypassTestCase(SimpleTestCase):
	"""No ``real_ssrf`` marker: conftest's resolver bypass applies here."""

	def test_unmocked_fetch_fails_without_touching_the_network(self) -> None:
		with (
			patch("monitoring.safe_fetch.socket.getaddrinfo", side_effect=AssertionError("unexpected DNS lookup")),
			patch("monitoring.safe_fetch.create_connection", side_effect=AssertionError("unexpected dial")),
			self.assertRaises(requests.ConnectionError) as failed,
		):
			safe_fetch.fetch("http://example.com/", timeout=5)
		self.assertIn("No validated address", str(failed.exception))
