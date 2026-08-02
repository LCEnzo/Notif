"""Outbound HTTP with SSRF guardrails: public-address-only + bounded bodies.

Every fetch the monitoring app makes must go through this module. Three
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

``NonPublicHostError`` and ``ResponseTooLargeError`` subclass
``requests.RequestException`` so existing call sites that already translate
``RequestException`` into ``Err`` results keep working unchanged.
"""

from __future__ import annotations

import ipaddress
import socket
from collections.abc import Mapping
from typing import Any
from urllib.parse import urljoin, urlsplit

import requests
from requests.adapters import HTTPAdapter
from urllib3.connection import HTTPConnection, HTTPSConnection
from urllib3.connectionpool import HTTPConnectionPool, HTTPSConnectionPool
from urllib3.poolmanager import PoolManager
from urllib3.util.connection import create_connection

MAX_RESPONSE_BYTES = 10 * 1024 * 1024
MAX_REDIRECTS = 5
_CHUNK_SIZE = 64 * 1024


class NonPublicHostError(requests.RequestException):
	"""The target host resolves to an address that must not be fetched."""


class ResponseTooLargeError(requests.RequestException):
	"""The response body exceeded MAX_RESPONSE_BYTES."""


def _address_is_public(address: str) -> bool:
	"""True when ``address`` is a globally routable IP literal.

	Uses ``is_global`` so private, loopback, link-local, reserved and
	unspecified ranges (IPv4 and IPv6 alike) are all rejected — including
	169.254.169.254-style cloud metadata and ::1. Multicast is excluded
	explicitly: ``is_global`` does not consistently cover it (e.g. ff02::1).
	"""
	try:
		ip = ipaddress.ip_address(address)
	except ValueError:
		return False
	return ip.is_global and not ip.is_multicast


def resolve_public_host(host: str) -> list[str]:
	"""Validate ``host`` and return its public addresses.

	Raises ``NonPublicHostError`` unless *every* A/AAAA record is public: a
	host with one public and one private record is exactly what a rebinding
	setup looks like. Also raises when the hostname does not resolve at all
	(``requests`` would fail anyway, and failing here keeps the error class
	uniform). The returned addresses are what connections are pinned to.
	"""
	if not host:
		raise NonPublicHostError("URL has no host.")
	try:
		infos = socket.getaddrinfo(host, None)
	except OSError as exc:
		raise NonPublicHostError(f"Host {host!r} does not resolve.") from exc
	if not infos:
		raise NonPublicHostError(f"Host {host!r} does not resolve.")
	addresses = [info[4][0] for info in infos]
	for address in addresses:
		if not _address_is_public(str(address)):
			raise NonPublicHostError(f"Host {host!r} resolves to a non-public address ({address}), which is refused.")
	return [str(address) for address in addresses]


class _PublicOnlyHTTPConnection(HTTPConnection):
	"""HTTPConnection that connects only to a pre-validated public address.

	``_new_conn`` resolves the hostname, validates every answer, and connects
	to one of the validated addresses — the exact resolution the validator
	saw, not a fresh lookup. ``self.host`` is untouched, so the Host header,
	TLS SNI and certificate verification keep using the real hostname.
	"""

	def _new_conn(self) -> socket.socket:
		addresses = resolve_public_host(self._dns_host)
		return create_connection(
			(addresses[0], self.port),
			self.timeout,
			source_address=self.source_address,
			socket_options=self.socket_options,
		)


class _PublicOnlyHTTPSConnection(_PublicOnlyHTTPConnection, HTTPSConnection):
	"""HTTPS variant: same pinned connect, TLS handshake against the hostname."""


class _PublicOnlyConnectionPool(HTTPConnectionPool):
	ConnectionCls = _PublicOnlyHTTPConnection


class _PublicOnlyHTTPSConnectionPool(HTTPSConnectionPool):
	ConnectionCls = _PublicOnlyHTTPSConnection


class _PublicOnlyPoolManager(PoolManager):
	pool_classes_by_scheme = {
		"http": _PublicOnlyConnectionPool,
		"https": _PublicOnlyHTTPSConnectionPool,
	}


class PublicOnlyHTTPAdapter(HTTPAdapter):
	"""HTTPAdapter whose connections are DNS-pinned to public addresses.

	``send`` keeps a cheap no-DNS fast path for literal private addresses so
	they fail before any pool work; the real enforcement is in the connection
	class, which runs for the initial request *and* every redirect hop.
	"""

	def __init__(self, **kwargs: Any) -> None:
		# requests' HTTPAdapter defaults (10 pools, 10 max, no blocking);
		# mirrored here because the stub types do not expose DEFAULT_POOLSIZE.
		pool_connections = kwargs.pop("pool_connections", 10)
		pool_maxsize = kwargs.pop("pool_maxsize", 10)
		pool_block = kwargs.pop("pool_block", False)
		super().__init__(
			pool_connections=pool_connections,
			pool_maxsize=pool_maxsize,
			pool_block=pool_block,
			**kwargs,
		)
		self.poolmanager = _PublicOnlyPoolManager(
			num_pools=pool_connections,
			maxsize=pool_maxsize,
			block=pool_block,
		)

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
		return super().send(
			request,
			stream=stream,
			timeout=timeout,
			verify=verify,
			cert=cert,
			proxies=proxies,
		)


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


def guarded_session() -> requests.Session:
	"""A Session whose http/https connections are pinned to public hosts."""
	session = requests.Session()
	# Environment proxies would route the connection through the proxy pool
	# instead of the pinned connection classes below, silently bypassing the
	# SSRF guard — so guarded fetches never inherit them. Operators should
	# enforce any required egress proxy separately.
	session.trust_env = False
	session.mount("https://", PublicOnlyHTTPAdapter())
	session.mount("http://", PublicOnlyHTTPAdapter())
	return session


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


def read_body_capped(response: requests.Response) -> bytes:
	"""Read a response body under the cap, for call sites that manage their
	own session (the QQ/Kemono login flows). Populates ``_content`` so
	``.text``/``.content`` work as usual afterwards."""
	content = _read_bounded(response)
	response._content = content
	return content


def fetch(url: str, *, timeout: float) -> requests.Response:
	"""GET ``url`` with the SSRF guard and a bounded body.

	Returns the response with ``_content`` populated (so ``.text``/``.content``
	work as usual) and the stream already consumed. Redirects are followed by
	hand (up to ``MAX_REDIRECTS``), with every hop validated by the pinned
	adapter and read under the cap. A fresh session per call means cookies do
	not survive across fetches. Raises ``requests.RequestException``
	subclasses — including ``NonPublicHostError``, ``ResponseTooLargeError``
	and ``requests.TooManyRedirects`` — on any failure.
	"""
	with guarded_session() as session:
		current = url
		for _hop in range(MAX_REDIRECTS + 1):
			with session.get(current, timeout=timeout, stream=True, allow_redirects=False) as response:
				content = _read_bounded(response)
			location = response.headers.get("Location")
			if response.is_redirect and location:
				current = urljoin(current, location)
				continue
			response._content = content
			return response
	raise requests.TooManyRedirects(f"Exceeded {MAX_REDIRECTS} redirects fetching {url}.")
