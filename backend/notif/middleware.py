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

from notif.config import settings


class DevLatencyMiddleware:
    """Add artificial latency to /api/ requests for frontend testing."""

    def __init__(self, get_response):
        self.get_response = get_response

    @property
    def active(self) -> bool:
        return settings.DEV_API_LATENCY_MS > 0 or settings.DEV_API_LATENCY_JITTER_MS > 0

    def __call__(self, request):
        if not self.active or not request.path.startswith("/api/"):
            return self.get_response(request)

        delay_ms = settings.DEV_API_LATENCY_MS + (
            random.randint(0, settings.DEV_API_LATENCY_JITTER_MS)
            if settings.DEV_API_LATENCY_JITTER_MS > 0
            else 0
        )
        time.sleep(delay_ms / 1000.0)

        return self.get_response(request)
