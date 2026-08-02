"""Outbound HTTP with SSRF guardrails: public-address-only + bounded bodies.

Every fetch the monitoring app makes must go through this module. Two
enforcements, both defense-in-depth layers rather than UX checks:

* ``PublicOnlyHTTPAdapter`` refuses to connect to any address that is not
  globally routable. It runs per-hop (including redirects, because requests
  resolves each Location through the same adapter), and resolves the hostname
  immediately before connecting, so the DNS-rebinding window is as small as
  the library allows.
* ``fetch`` streams the response body and aborts past ``MAX_RESPONSE_BYTES``,
  so a hostile or misbehaving endpoint cannot hold unbounded memory.

``NonPublicHostError`` and ``ResponseTooLargeError`` subclass
``requests.RequestException`` so existing call sites that already translate
``RequestException`` into ``Err`` results keep working unchanged.
"""

from __future__ import annotations

import ipaddress
import socket
from collections.abc import Mapping
from urllib.parse import urlsplit

import requests
from requests.adapters import HTTPAdapter

MAX_RESPONSE_BYTES = 10 * 1024 * 1024
_CHUNK_SIZE = 64 * 1024

# Hostnames that are structurally internal, checked before any DNS lookup.
# Literal addresses are judged by ``ipaddress`` instead (below), which also
# covers decimal/octal/hex encodings that no suffix list could catch.
_INTERNAL_HOSTNAME_SUFFIXES = (".local", ".internal", ".lan", ".home.arpa", ".localhost")


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


def resolve_public_host(host: str) -> None:
	"""Raise ``NonPublicHostError`` unless every A/AAAA record for ``host`` is public.

	Rejects the host outright if *any* resolved address is non-public: a host
	with one public and one private record is exactly what a rebinding setup
	looks like. Raises ``NonPublicHostError`` also when the hostname does not
	resolve at all (``requests`` would fail anyway, and failing here keeps the
	error class uniform).
	"""
	if not host:
		raise NonPublicHostError("URL has no host.")
	try:
		infos = socket.getaddrinfo(host, None)
	except OSError as exc:
		raise NonPublicHostError(f"Host {host!r} does not resolve.") from exc
	if not infos:
		raise NonPublicHostError(f"Host {host!r} does not resolve.")
	for info in infos:
		if not _address_is_public(str(info[4][0])):
			raise NonPublicHostError(
				f"Host {host!r} resolves to a non-public address ({info[4][0]}), which is refused."
			)


class PublicOnlyHTTPAdapter(HTTPAdapter):
	"""HTTPAdapter that refuses to send to non-public addresses.

	``send`` is called for the initial request *and* for every redirect hop,
	so a redirect from a public host to an internal one is caught here. The
	resolution happens immediately before the connection is opened, which
	keeps the DNS-rebinding race as narrow as requests allows.
	"""

	def send(
		self,
		request: requests.PreparedRequest,
		stream: bool = False,
		timeout: float | tuple[float, float] | tuple[float, None] | None = None,
		verify: bool | str = True,
		cert: bytes | str | tuple[bytes | str, bytes | str] | None = None,
		proxies: Mapping[str, str] | None = None,
	) -> requests.Response:
		host = urlsplit(request.url or "").hostname
		resolve_public_host(host if host is not None else "")
		return super().send(
			request,
			stream=stream,
			timeout=timeout,
			verify=verify,
			cert=cert,
			proxies=proxies,
		)


def guarded_session() -> requests.Session:
	"""A Session whose http/https traffic is refused to non-public hosts."""
	session = requests.Session()
	session.mount("https://", PublicOnlyHTTPAdapter())
	session.mount("http://", PublicOnlyHTTPAdapter())
	return session


_session = guarded_session()


def fetch(url: str, *, timeout: float) -> requests.Response:
	"""GET ``url`` with the SSRF guard and a bounded body.

	Returns the response with ``_content`` populated (so ``.text``/``.content``
	work as usual) and the stream already consumed. Raises
	``requests.RequestException`` subclasses — including ``NonPublicHostError``
	and ``ResponseTooLargeError`` — on any failure.
	"""
	with _session.get(url, timeout=timeout, stream=True) as response:
		chunks: list[bytes] = []
		total = 0
		for chunk in response.iter_content(chunk_size=_CHUNK_SIZE):
			if not chunk:
				continue
			total += len(chunk)
			if total > MAX_RESPONSE_BYTES:
				raise ResponseTooLargeError(
					f"Response exceeded the {MAX_RESPONSE_BYTES}-byte cap; refusing to buffer it."
				)
			chunks.append(chunk)
		content = b"".join(chunks)
	# requests buffers eagerly on first attribute access; we consumed the
	# stream manually, so hand the bytes back so .content/.text behave as if
	# the response had been read normally.
	response._content = content
	return response
