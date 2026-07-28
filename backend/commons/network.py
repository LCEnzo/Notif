from __future__ import annotations

from rest_framework.request import Request


def client_ip(request: Request) -> str:
	forwarded = request.META.get("HTTP_X_FORWARDED_FOR", "")
	if isinstance(forwarded, str) and forwarded:
		return forwarded.split(",", 1)[0].strip()

	remote_addr = request.META.get("REMOTE_ADDR", "")
	if isinstance(remote_addr, str):
		return remote_addr
	return ""
