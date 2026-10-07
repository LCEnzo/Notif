"""Outbound HTTP with SSRF guardrails: public-address-only + bounded bodies.

Every fetch the monitoring app makes must go through this module. Four
enforcements, all defense-in-depth layers rather than UX checks:

* Connections are **DNS-pinned**: the socket connects to an address that was
  resolved and validated in the same call, so a rebinding DNS server cannot
  answer "public" to the validator and "private" to the connector. The Host
  header, TLS SNI and certificate verification all keep using the hostname.
* **Redirects are followed by hand**, each hop re-validated by the pinned
  adapter and each hop's body read under ``MAX_RESPONSE_BYTES`` — a hostile
  302 cannot smuggle an unbounded body past the cap.
* ``fetch`` uses a **fresh session per call**, so cookies set by one target
  never leak into another user's scrape of the same host.
* A guarded session has a **wall-clock deadline** (``FETCH_DEADLINE_SECONDS``)
  covering every hop, connect and read — DNS lookups excepted, which only the
  system resolver bounds — so a server that drips bytes slower than the
  socket timeout cannot hold a scrape open indefinitely.

``NonPublicHostError``, ``ResponseTooLargeError`` and ``DeadlineExceededError``
subclass ``requests.RequestException`` so call sites that already translate
``RequestException`` into ``Err`` results keep working unchanged.
"""

from __future__ import annotations

import ipaddress
import logging
import socket
import sys
import threading
import time
from collections.abc import Iterator, Mapping
from contextlib import contextmanager, suppress
from contextvars import ContextVar, Token
from typing import Any, Literal, override
from urllib.parse import urljoin, urlsplit

import requests
from requests.adapters import DEFAULT_POOLBLOCK, HTTPAdapter
from urllib3.connection import HTTPConnection, HTTPSConnection
from urllib3.connectionpool import HTTPConnectionPool, HTTPSConnectionPool
from urllib3.exceptions import ConnectTimeoutError, LocationParseError, NewConnectionError
from urllib3.poolmanager import PoolManager
from urllib3.util import parse_url
from urllib3.util.connection import create_connection

logger = logging.getLogger(__name__)

MAX_RESPONSE_BYTES = 10 * 1024 * 1024
MAX_REDIRECTS = 5
FETCH_DEADLINE_SECONDS = 60.0
_CHUNK_SIZE = 64 * 1024
_NAT64 = ipaddress.IPv6Network("64:ff9b::/96")
_IPV4_COMPATIBLE = ipaddress.IPv6Network("::/96")
# Ranges ``is_global`` calls public that must still never be dialled.
# IPv4-translated addresses (RFC 2765) embed an IPv4 address the way
# IPv4-mapped ones do, but ``is_global`` only unwraps the mapped form. Site-
# local (RFC 3879) and the 6to4 relay anycast (RFC 7526) are deprecated and
# not globally routed. 168.63.129.16 is Azure's platform endpoint, reachable
# only from inside a VM on the host.
_NON_PUBLIC_DESPITE_IS_GLOBAL = (
	ipaddress.IPv6Network("::ffff:0:0:0/96"),
	ipaddress.IPv6Network("fec0::/10"),
	ipaddress.IPv4Network("192.88.99.0/24"),
	ipaddress.IPv4Network("168.63.129.16/32"),
)


class NonPublicHostError(requests.RequestException):
	"""The target host resolves to an address that must not be fetched."""


class ResponseTooLargeError(requests.RequestException):
	"""The response body exceeded MAX_RESPONSE_BYTES."""


class DeadlineExceededError(requests.Timeout):
	"""A guarded session ran past FETCH_DEADLINE_SECONDS."""


def _address_is_public(address: str) -> bool:
	"""True when ``address`` is a globally routable IP literal.

	Uses ``is_global`` so private, loopback, link-local, reserved and
	unspecified ranges (IPv4 and IPv6 alike) are all rejected — including
	169.254.169.254-style cloud metadata and ::1. Multicast is excluded
	explicitly: ``is_global`` does not consistently cover it (e.g. ff02::1).
	NAT64 (64:ff9b::/96) and IPv4-compatible (::/96) addresses are judged by
	the IPv4 address in their low 32 bits, which ``is_global`` ignores. The
	ranges in ``_NON_PUBLIC_DESPITE_IS_GLOBAL`` are refused outright, after
	that unwrapping, so an embedded copy of one is refused too.
	"""
	try:
		ip = ipaddress.ip_address(address)
	except ValueError:
		return False
	if isinstance(ip, ipaddress.IPv6Address) and (ip in _NAT64 or ip in _IPV4_COMPATIBLE):
		ip = ipaddress.IPv4Address(int(ip) & 0xFFFFFFFF)
	if any(ip in network for network in _NON_PUBLIC_DESPITE_IS_GLOBAL):
		return False
	return ip.is_global and not ip.is_multicast


def resolve_public_host(host: str) -> list[str]:
	"""Validate ``host`` and return its public addresses.

	Raises ``NonPublicHostError`` unless *every* A/AAAA record is public: a
	host with one public and one private record is exactly what a rebinding
	setup looks like. Also raises when the hostname does not resolve at all
	(``requests`` would fail anyway, and failing here keeps the error class
	uniform). The returned addresses, deduplicated in resolver order, are what
	connections are pinned to.
	"""
	if not host:
		raise NonPublicHostError("URL has no host.")
	try:
		# SOCK_STREAM: without a socket type, glibc answers each address once
		# per protocol (stream, datagram, raw).
		infos = socket.getaddrinfo(host, None, type=socket.SOCK_STREAM)
	except OSError as exc:
		raise NonPublicHostError(f"Host {host!r} does not resolve.") from exc
	if not infos:
		raise NonPublicHostError(f"Host {host!r} does not resolve.")
	addresses = list(dict.fromkeys(str(info[4][0]) for info in infos))
	for address in addresses:
		if not _address_is_public(address):
			# The address goes to the log only: the exception text reaches the
			# link's owner (last_scrape_error, the scrape API), and echoing what
			# an internal name resolves to would map the compose network for them.
			logger.warning("Refused host %r: it resolves to the non-public address %s.", host, address)
			raise NonPublicHostError(f"Host {host!r} resolves to a non-public address, which is refused.")
	return addresses


class _NonPublicHostBlockedError(Exception):
	"""Internal signal that the pinned connection refused a non-public host.

	Deliberately *not* a ``NonPublicHostError``: that class subclasses
	``requests.RequestException``, which is an ``OSError``, and urllib3's pool
	machinery catches ``OSError`` around the connect path — the refusal would
	be wrapped into ``ProtocolError``, fed to retry accounting, and surface as
	a generic ``requests.ConnectionError`` with the real cause buried three
	wrappers deep. A plain ``Exception`` subclass passes through urllib3 and
	requests untouched; ``PublicOnlyHTTPAdapter.send`` translates it back.
	"""


class _PublicOnlyHTTPConnection(HTTPConnection):
	"""HTTPConnection that connects only to a pre-validated public address.

	``_new_conn`` resolves the hostname, validates every answer, and connects
	to the validated addresses — the exact resolution the validator saw, not
	a fresh lookup. ``self.host`` is untouched, so the Host header, TLS SNI
	and certificate verification keep using the real hostname.

	Otherwise it mirrors urllib3's ``HTTPConnection._new_conn``: addresses are
	tried in resolver order, and the last failure is translated into
	``ConnectTimeoutError`` / ``NewConnectionError``. A raw ``OSError`` here
	would be misfiled by the pool — an HTTPS connect timeout as a *read*
	timeout, anything else as an aborted connection.
	"""

	def _new_conn(self) -> socket.socket:
		try:
			addresses = resolve_public_host(self._dns_host)
		except NonPublicHostError as exc:
			raise _NonPublicHostBlockedError(str(exc)) from exc
		deadline = _active_deadline.get()
		error: OSError = OSError(f"No validated address to connect to for {self.host!r}.")
		for address in addresses:
			try:
				sock = create_connection(
					(address, self.port),
					self.timeout if deadline is None else deadline.clip_connect_timeout(self.timeout),
					source_address=self.source_address,
					socket_options=self.socket_options,
				)
			except OSError as exc:
				error = exc
				continue
			if deadline is not None:
				deadline.watch(sock)
			sys.audit("http.client.connect", self, self.host, self.port)
			return sock
		if isinstance(error, TimeoutError):
			raise ConnectTimeoutError(
				self, f"Connection to {self.host} timed out. (connect timeout={self.timeout})"
			) from error
		raise NewConnectionError(self, f"Failed to establish a new connection: {error}") from error


class _PublicOnlyHTTPSConnection(_PublicOnlyHTTPConnection, HTTPSConnection):
	"""HTTPS variant: same pinned connect, TLS handshake against the hostname."""


class _PublicOnlyConnectionPool(HTTPConnectionPool):
	ConnectionCls = _PublicOnlyHTTPConnection


class _PublicOnlyHTTPSConnectionPool(HTTPSConnectionPool):
	ConnectionCls = _PublicOnlyHTTPSConnection


class _PublicOnlyPoolManager(PoolManager):
	"""PoolManager whose pools build the pinned connection classes.

	urllib3's ``PoolManager.__init__`` assigns ``self.pool_classes_by_scheme``
	as an *instance* attribute, so a class-level override here would be
	silently shadowed and stock, unpinned pools would run. The override must
	be assigned after ``super().__init__()``.
	"""

	def __init__(self, *args: Any, **kwargs: Any) -> None:
		super().__init__(*args, **kwargs)
		self.pool_classes_by_scheme = {
			"http": _PublicOnlyConnectionPool,
			"https": _PublicOnlyHTTPSConnectionPool,
		}


class PublicOnlyHTTPAdapter(HTTPAdapter):
	"""HTTPAdapter whose connections are DNS-pinned to public addresses.

	``send`` keeps a cheap no-DNS fast path for literal private addresses so
	they fail before any pool work; the real enforcement is in the connection
	class, which runs for the initial request *and* every redirect hop.
	"""

	@override
	def init_poolmanager(
		self,
		connections: int,
		maxsize: int,
		block: bool = DEFAULT_POOLBLOCK,
		**pool_kwargs: Any,
	) -> None:
		# The canonical requests extension point: HTTPAdapter.__init__ *and*
		# __setstate__ both route through here, so the pinned pool manager
		# survives construction and unpickling alike.
		self.poolmanager = _PublicOnlyPoolManager(
			num_pools=connections,
			maxsize=maxsize,
			block=block,
			**pool_kwargs,
		)

	@override
	def send(
		self,
		request: requests.PreparedRequest,
		stream: bool = False,
		timeout: float | tuple[float, float] | tuple[float, None] | None = None,
		verify: bool | str = True,
		cert: bytes | str | tuple[bytes | str, bytes | str] | None = None,
		proxies: Mapping[str, str] | None = None,
	) -> requests.Response:
		if proxies:
			# An explicit proxy would move the connection outside this
			# adapter's validated-address boundary; refuse rather than
			# silently unpin.
			raise NonPublicHostError("proxy routing is disabled for SSRF-guarded fetches")
		host = urlsplit(request.url or "").hostname
		if host is not None:
			_reject_literal_private_host(host)
		try:
			return super().send(
				request,
				stream=stream,
				timeout=timeout,
				verify=verify,
				cert=cert,
				proxies=proxies,
			)
		except _NonPublicHostBlockedError as blocked:
			raise NonPublicHostError(str(blocked), request=request) from blocked


def _reject_literal_private_host(host: str) -> None:
	"""Fast, no-DNS rejection of plain private IP literals.

	Encoded forms (decimal/hex, ``localhost``, single-label names) fall
	through to the pinned resolver, which handles them.
	"""
	try:
		ipaddress.ip_address(host)
	except ValueError:
		return
	if not _address_is_public(host):
		raise NonPublicHostError(f"Host {host!r} is a non-public address, which is refused.")


def reject_non_public_literal(url: str) -> None:
	"""Refuse ``url`` when its host is a non-public IP literal or a localhost
	name: the checks that need no DNS lookup.

	The host is read with urllib3's parser, the one the transport dials with,
	because ``urlsplit`` can disagree: it reads ``http://127.0.0.1\\@example.com/``
	as example.com, where urllib3 dials 127.0.0.1. Hostnames, and IPv4 written
	in decimal or hex, are not resolved here; the pinned connection validates
	whatever they resolve to at fetch time.
	"""
	try:
		host = parse_url(url).host
	except LocationParseError as exc:
		raise NonPublicHostError(f"URL {url!r} cannot be parsed.") from exc
	if not host:
		raise NonPublicHostError("URL has no host.")
	host = host.strip("[]").rstrip(".")
	if host == "localhost" or host.endswith(".localhost"):
		raise NonPublicHostError(f"Host {host!r} is a loopback name, which is refused.")
	_reject_literal_private_host(host)


class _Deadline:
	"""Wall-clock budget for one guarded session, enforced from outside the I/O.

	Socket timeouts bound each ``recv``, not their sum: a server that drips a
	byte per timeout window holds a header or body read open indefinitely.
	So when the budget runs out a timer shuts down every socket the session
	opened, which fails whatever read is blocked on it. Connect attempts are
	clipped to the remaining budget instead, as their sockets are only watched
	once connected. DNS lookups cannot be interrupted; the system resolver's
	own timeouts bound them.
	"""

	_token: Token[_Deadline | None]

	def __init__(self, seconds: float) -> None:
		self._expires_at = time.monotonic() + seconds
		self._timer = threading.Timer(seconds, self._expire)
		self._timer.daemon = True
		self._lock = threading.Lock()
		self._fired = False
		self._watched: list[socket.socket] = []

	@property
	def expired(self) -> bool:
		return self._fired or time.monotonic() >= self._expires_at

	def clip_connect_timeout(self, timeout: object) -> float:
		remaining = self._expires_at - time.monotonic()
		if remaining <= 0:
			raise TimeoutError("The fetch deadline passed before connecting.")
		return min(timeout, remaining) if isinstance(timeout, int | float) else remaining

	def watch(self, sock: socket.socket) -> None:
		# Watch a duplicate: wrapping the socket for TLS detaches the original
		# object, but a duplicate stays valid, and shutting it down ends the
		# connection both share. It is closed when the session ends.
		duplicate = sock.dup()
		with self._lock:
			self._watched.append(duplicate)
			if self._fired:
				_shut_down(duplicate)

	def _expire(self) -> None:
		with self._lock:
			self._fired = True
			for watched in self._watched:
				_shut_down(watched)

	def __enter__(self) -> _Deadline:
		self._token = _active_deadline.set(self)
		self._timer.start()
		return self

	def __exit__(self, *exc_info: object) -> None:
		self._timer.cancel()
		_active_deadline.reset(self._token)
		with self._lock:
			for watched in self._watched:
				watched.close()
			self._watched.clear()


def _shut_down(sock: socket.socket) -> None:
	# Already closed by its peer or never fully connected: nothing left to interrupt.
	with suppress(OSError):
		sock.shutdown(socket.SHUT_RDWR)


# The deadline of the guarded session running in this context, read by the
# pinned connection, which urllib3 constructs without any way to pass it in.
_active_deadline: ContextVar[_Deadline | None] = ContextVar("safe_fetch_deadline", default=None)


@contextmanager
def guarded_session() -> Iterator[requests.Session]:
	"""A Session whose http/https connections are pinned to public hosts, for
	at most ``FETCH_DEADLINE_SECONDS`` of wall-clock time.

	Past the deadline, requests on it fail with ``DeadlineExceededError`` —
	also when the interrupted read ended cleanly, since a body without a
	declared length that just stops can look complete.
	"""
	session = requests.Session()
	# Environment proxies would route the connection through the proxy pool
	# instead of the pinned connection classes below, silently bypassing the
	# SSRF guard — so guarded fetches never inherit them. Operators should
	# enforce any required egress proxy separately.
	session.trust_env = False
	session.mount("https://", PublicOnlyHTTPAdapter())
	session.mount("http://", PublicOnlyHTTPAdapter())
	exceeded = f"Gave up at the {FETCH_DEADLINE_SECONDS:g}-second fetch deadline."
	with session, _Deadline(FETCH_DEADLINE_SECONDS) as deadline:
		try:
			yield session
		except requests.RequestException as exc:
			if not deadline.expired or isinstance(exc, NonPublicHostError | ResponseTooLargeError):
				raise
			raise DeadlineExceededError(exceeded) from exc
		if deadline.expired:
			raise DeadlineExceededError(exceeded)


def _read_bounded(response: requests.Response) -> bytes:
	chunks: list[bytes] = []
	total = 0
	for chunk in response.iter_content(chunk_size=_CHUNK_SIZE):
		if not chunk:
			continue
		total += len(chunk)
		if total > MAX_RESPONSE_BYTES:
			raise ResponseTooLargeError(f"Response exceeded the {MAX_RESPONSE_BYTES}-byte cap; refusing to buffer it.")
		chunks.append(chunk)
	return b"".join(chunks)


def request_capped(
	session: requests.Session,
	method: Literal["GET", "POST"],
	url: str,
	*,
	timeout: float,
	allow_redirects: bool,
	data: Mapping[str, str] | None = None,
) -> requests.Response:
	"""Send one request on a guarded session and read its body under the cap.

	The request always streams, so the cap bounds what is buffered instead of
	being checked after requests has already read everything. The body is in
	``.content``/``.text`` and the connection is released on return.

	With ``allow_redirects=True`` requests follows redirects itself: it reads
	each intermediate hop's body into memory uncapped (every hop is still
	pinned by the adapter), and on a 307/308 it resends a POST body,
	credentials included, to the new location, even on another host. Only
	hard-coded first-party flows that need the redirect (QQ's login) should
	do that; ``fetch`` follows redirects by hand instead.
	"""
	with session.request(
		method, url, data=data, timeout=timeout, allow_redirects=allow_redirects, stream=True
	) as response:
		response._content = _read_bounded(response)
	return response


def fetch(url: str, *, timeout: float) -> requests.Response:
	"""GET ``url`` with the SSRF guard and a bounded body.

	Returns the response with ``_content`` populated (so ``.text``/``.content``
	work as usual) and the stream already consumed. Redirects are followed by
	hand (up to ``MAX_REDIRECTS``), with every hop validated by the pinned
	adapter and read under the cap, all within ``FETCH_DEADLINE_SECONDS``;
	``timeout`` still bounds each connect and each read. A fresh session per
	call means cookies do not survive across fetches. Raises
	``requests.RequestException`` subclasses — including ``NonPublicHostError``,
	``ResponseTooLargeError``, ``DeadlineExceededError`` and
	``requests.TooManyRedirects`` — on any failure.
	"""
	with guarded_session() as session:
		current = url
		for _hop in range(MAX_REDIRECTS + 1):
			response = request_capped(session, "GET", current, timeout=timeout, allow_redirects=False)
			location = response.headers.get("Location")
			if not (response.is_redirect and location):
				return response
			current = urljoin(current, location)
	raise requests.TooManyRedirects(f"Exceeded {MAX_REDIRECTS} redirects fetching {url}.")
