from typing import cast
from unittest.mock import patch

from django.core import mail
from django.core.mail import EmailMultiAlternatives
from django.test import TestCase

from commons.email import send_password_reset_email


class SendPasswordResetEmailTestCase(TestCase):
	def test_sends_email_with_correct_metadata(self):
		send_password_reset_email("user@example.com", "123456")

		self.assertEqual(len(mail.outbox), 1)
		msg = cast(EmailMultiAlternatives, mail.outbox[0])
		self.assertEqual(msg.subject, "Reset your Notif password")
		self.assertEqual(msg.to, ["user@example.com"])
		self.assertIn("notif@", msg.from_email)

	def test_includes_reset_code_in_both_formats(self):
		send_password_reset_email("user@example.com", "654321")

		msg = cast(EmailMultiAlternatives, mail.outbox[0])
		self.assertIn("654321", msg.body)
		html: str = msg.alternatives[0][0]  # type: ignore[assignment]
		self.assertIn("654321", html)
		self.assertEqual(msg.alternatives[0][1], "text/html")

	def test_has_text_and_html_alternatives(self):
		send_password_reset_email("user@example.com", "111111")

		msg = cast(EmailMultiAlternatives, mail.outbox[0])
		self.assertIn("Your reset code is:", msg.body)
		html: str = msg.alternatives[0][0]  # type: ignore[assignment]
		self.assertIn("<p>Your reset code is:</p>", html)
		self.assertIn("30 minutes", msg.body)
		self.assertIn("30 minutes", html)

	def test_reraises_on_send_failure(self):
		with patch("commons.email.EmailMultiAlternatives.send") as mock_send:
			mock_send.side_effect = ConnectionError("SMTP down")

			with self.assertRaises(ConnectionError):
				send_password_reset_email("user@example.com", "999999")

	def test_logs_on_failure(self):
		with (
			patch("commons.email.EmailMultiAlternatives.send") as mock_send,
		):
			mock_send.side_effect = ConnectionError("SMTP down")

			with self.assertLogs("commons.email", level="ERROR") as logs, self.assertRaises(ConnectionError):
				send_password_reset_email("user@example.com", "888888")

		self.assertTrue(any("Failed to send password reset email to user@example.com" in msg for msg in logs.output))
