import time
from urllib.parse import urlsplit

DEFAULT_DOMAIN_DELAY = 2.0


class DomainRateLimiter:
	"""
	Per-domain rate limiter. Ensures at least `delay` seconds between
	requests to the same domain. Resets each run (no persistence).
	"""
	def __init__(self, delay: float = DEFAULT_DOMAIN_DELAY):
		self._delay = delay
		self._last_request: dict[str, float] = {}

	def wait_for_domain(self, url: str) -> None:
		domain = urlsplit(url).netloc
		now = time.monotonic()
		last = self._last_request.get(domain, 0.0)
		wait = self._delay - (now - last)
		if wait > 0:
			time.sleep(wait)
		self._last_request[domain] = time.monotonic()
