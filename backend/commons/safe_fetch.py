"""SSRF-hardened outbound HTTP fetch.

Scrapers fetch user-supplied URLs, so every such fetch must go through
``safe_get`` rather than calling ``requests`` directly. It:

* allows only ``http``/``https`` schemes (``file``/``ftp``/``gopher`` are refused);
* resolves the host and refuses any private / loopback / link-local / reserved /
  multicast / unspecified address (this covers the ``169.254.169.254`` cloud
  metadata endpoint and internal Docker/LAN addresses);
* validates every redirect hop rather than only the initial URL;
* caps the response body so a hostile endpoint cannot exhaust memory.

Known residual — DNS rebinding (TOCTOU): validation resolves the host, but
``requests`` re-resolves at connect time, so a hostile DNS record that flips to
an internal address between check and connect is not caught. Closing that needs
a connection-level IP pin (a custom adapter); see ``docs/TODO.md``.
"""

from __future__ import annotations

import ipaddress
import socket
from urllib.parse import urljoin, urlsplit

import requests

DEFAULT_FETCH_TIMEOUT_SECONDS = 30
DEFAULT_MAX_BYTES = 16 * 1024 * 1024
DEFAULT_MAX_REDIRECTS = 5
_ALLOWED_SCHEMES = frozenset({"http", "https"})


class UnsafeUrlError(requests.RequestException):
	"""A URL was refused before or during fetching because it targets a
	disallowed scheme or a non-public address.

	Subclasses ``requests.RequestException`` so existing
	``except requests.RequestException`` handlers treat a refusal as an ordinary
	fetch failure instead of an uncaught crash.
	"""


def _resolve(host: str, port: int) -> list[str]:
	"""Resolve ``host`` to its IP addresses. Module-level so tests can stub it."""
	return [str(info[4][0]) for info in socket.getaddrinfo(host, port, proto=socket.IPPROTO_TCP)]


def assert_url_is_public(url: str) -> None:
	"""Raise :class:`UnsafeUrlError` if ``url`` is not an http(s) URL resolving
	exclusively to public addresses."""
	parsed = urlsplit(url)
	scheme = parsed.scheme.lower()
	if scheme not in _ALLOWED_SCHEMES:
		raise UnsafeUrlError(f"refused to fetch non-HTTP(S) URL (scheme {scheme!r})")

	host = parsed.hostname
	if not host:
		raise UnsafeUrlError("refused to fetch URL with no host")

	port = parsed.port or (443 if scheme == "https" else 80)
	try:
		addresses = _resolve(host, port)
	except OSError as exc:
		raise UnsafeUrlError(f"could not resolve host {host!r}") from exc
	if not addresses:
		raise UnsafeUrlError(f"could not resolve host {host!r}")

	for address in addresses:
		ip = ipaddress.ip_address(address)
		if (
			ip.is_private
			or ip.is_loopback
			or ip.is_link_local
			or ip.is_reserved
			or ip.is_multicast
			or ip.is_unspecified
		):
			raise UnsafeUrlError(f"refused to fetch internal address {ip} (host {host!r})")


def safe_get(
	url: str,
	*,
	timeout: float = DEFAULT_FETCH_TIMEOUT_SECONDS,
	max_bytes: int = DEFAULT_MAX_BYTES,
	max_redirects: int = DEFAULT_MAX_REDIRECTS,
) -> requests.Response:
	"""GET ``url`` with SSRF protections and a bounded body.

	Redirects are followed manually so each hop is re-validated. Returns a
	``requests.Response`` whose body is already materialised (so ``.text`` /
	``.content`` work). Raises :class:`UnsafeUrlError` on any refused hop, an
	over-large body, or too many redirects; other transport errors propagate as
	their usual ``requests`` exceptions.
	"""
	current = url
	with requests.Session() as session:
		for _ in range(max_redirects + 1):
			assert_url_is_public(current)
			response = session.get(current, timeout=timeout, allow_redirects=False, stream=True)
			if response.is_redirect:
				location = response.headers.get("location")
				response.close()
				if not location:
					raise UnsafeUrlError("redirect response missing Location header")
				current = urljoin(current, location)
				continue
			_materialise_bounded_body(response, max_bytes)
			return response
	raise UnsafeUrlError(f"refused to follow more than {max_redirects} redirects")


def _materialise_bounded_body(response: requests.Response, max_bytes: int) -> None:
	chunks: list[bytes] = []
	total = 0
	for chunk in response.iter_content(chunk_size=64 * 1024):
		if not chunk:
			continue
		total += len(chunk)
		if total > max_bytes:
			response.close()
			raise UnsafeUrlError(f"response body exceeded {max_bytes} bytes")
		chunks.append(chunk)
	response._content = b"".join(chunks)
	response._content_consumed = True  # type: ignore[attr-defined]
