"""Email sending through Django's configured email backend.

Single-responsibility module — only handles sending.
What to send and when is the caller's concern.
"""

import logging

from django.conf import settings
from django.core.mail import EmailMultiAlternatives

logger = logging.getLogger(__name__)


def send_password_reset_email(to_email: str, code: str) -> None:
	"""Send a 6-digit password reset code.

	The actual transport is controlled by Django EMAIL_* settings. Local
	development defaults to the console backend, while production can use
	Resend's SMTP endpoint or any other SMTP provider.
	"""
	try:
		text_body = (
			"Someone requested a password reset for your Notif account.\n\n"
			f"Your reset code is: {code}\n\n"
			"This code expires in 30 minutes.\n\n"
			"If you didn't request this, you can ignore this email."
		)
		html_body = (
			"<p>Someone requested a password reset for your Notif account.</p>"
			"<p>Your reset code is:</p>"
			'<p style="font-size:24px;font-weight:bold;letter-spacing:4px">'
			f"{code}</p>"
			"<p>This code expires in 30 minutes.</p>"
			"<p>If you didn't request this, you can ignore this email.</p>"
		)
		message = EmailMultiAlternatives(
			subject="Reset your Notif password",
			body=text_body,
			from_email=settings.EMAIL_FROM,
			to=[to_email],
		)
		message.attach_alternative(html_body, "text/html")
		message.send(fail_silently=False)
	except Exception:
		logger.exception("Failed to send password reset email to %s", to_email)
		raise
