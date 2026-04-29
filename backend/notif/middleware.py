"""
Dev-only middleware for testing frontend latency tolerance.

Activate by setting one or both of these env vars (nonzero):
  DEV_API_LATENCY_MS=100        — fixed delay per /api/ request
  DEV_API_LATENCY_JITTER_MS=50  — random extra delay in [0, JITTER] ms

When neither is set (or both are 0), the middleware passes through
with zero overhead.  Only applies to paths starting with /api/.
"""

import random
import time
from os import getenv


class DevLatencyMiddleware:
    """Add artificial latency to /api/ requests for frontend testing."""

    def __init__(self, get_response):
        self.get_response = get_response
        raw_base = getenv("DEV_API_LATENCY_MS", "0")
        raw_jitter = getenv("DEV_API_LATENCY_JITTER_MS", "0")
        self._base_ms = int(raw_base) if raw_base.isdigit() else 0
        self._jitter_ms = int(raw_jitter) if raw_jitter.isdigit() else 0

    @property
    def active(self) -> bool:
        return self._base_ms > 0 or self._jitter_ms > 0

    def __call__(self, request):
        if not self.active or not request.path.startswith("/api/"):
            return self.get_response(request)

        delay_ms = self._base_ms + (
            random.randint(0, self._jitter_ms) if self._jitter_ms > 0 else 0
        )
        time.sleep(delay_ms / 1000.0)

        return self.get_response(request)
