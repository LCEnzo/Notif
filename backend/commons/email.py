"""Email sending via Resend.

Single-responsibility module — only handles sending.
What to send and when is the caller's concern.
"""

import logging

from django.conf import settings

logger = logging.getLogger(__name__)


def _get_resend():
	"""Lazy-import resend and configure the API key.

	Done lazily so the module can be imported even when resend
	isn't installed (e.g. during mypy runs before uv sync).
	"""
	import resend as _resend

	_resend.api_key = settings.RESEND_API_KEY
	return _resend


def send_password_reset_email(to_email: str, code: str) -> None:
	"""Send a 6-digit password reset code.

	If RESEND_API_KEY is empty, the code is logged at WARNING level
	instead (dev fallback).
	"""
	if not settings.RESEND_API_KEY:
		logger.warning(
			"RESEND_API_KEY not set — password reset code for %s: %s",
			to_email,
			code,
		)
		return

	try:
		resend = _get_resend()
		resend.Emails.send(
			{
				"from": settings.EMAIL_FROM,
				"to": [to_email],
				"subject": "Reset your Notif password",
				"html": (
					f"<p>Someone (hopefully you) requested a password reset "
					f"for your Notif account.</p>"
					f"<p>Your reset code is:</p>"
					f'<p style="font-size:24px;font-weight:bold;letter-spacing:4px">'
					f"{code}</p>"
					f"<p>This code expires in 30 minutes.</p>"
					f"<p>If you didn't request this, you can ignore this email.</p>"
				),
			}
		)
	except Exception:
		logger.exception("Failed to send password reset email to %s", to_email)
		raise
