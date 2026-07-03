from typing import cast
from unittest.mock import patch

import requests
import requests_mock
from django.core import mail
from django.core.mail import EmailMultiAlternatives
from django.test import TestCase

from commons.email import send_password_reset_email
from commons.safe_fetch import UnsafeUrlError, safe_get


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
		html = msg.alternatives[0][0]
		assert isinstance(html, str), f"Expected str alternative, got {type(html)}"
		self.assertIn("654321", html)
		self.assertEqual(msg.alternatives[0][1], "text/html")

	def test_has_text_and_html_alternatives(self):
		send_password_reset_email("user@example.com", "111111")

		msg = cast(EmailMultiAlternatives, mail.outbox[0])
		self.assertIn("Your reset code is:", msg.body)
		html = msg.alternatives[0][0]
		assert isinstance(html, str), f"Expected str alternative, got {type(html)}"
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


class SafeFetchTestCase(TestCase):
	"""SSRF guard: safe_get must reject non-public targets and disallowed schemes.

	Uses IP-literal URLs so socket.getaddrinfo resolves numerically (no real DNS),
	keeping these tests offline-safe.
	"""

	def test_is_a_requests_exception(self):
		# So existing `except requests.RequestException` handlers treat a refused
		# URL as an ordinary fetch failure.
		self.assertTrue(issubclass(UnsafeUrlError, requests.RequestException))

	def test_rejects_loopback(self):
		with self.assertRaises(UnsafeUrlError):
			safe_get("http://127.0.0.1/")

	def test_rejects_cloud_metadata_link_local(self):
		with self.assertRaises(UnsafeUrlError):
			safe_get("http://169.254.169.254/latest/meta-data/")

	def test_rejects_private_range(self):
		with self.assertRaises(UnsafeUrlError):
			safe_get("http://10.0.0.1/")

	def test_rejects_ipv6_loopback(self):
		with self.assertRaises(UnsafeUrlError):
			safe_get("http://[::1]/")

	def test_rejects_non_http_schemes(self):
		with self.assertRaises(UnsafeUrlError):
			safe_get("file:///etc/passwd")
		with self.assertRaises(UnsafeUrlError):
			safe_get("ftp://93.184.216.34/file.txt")

	def test_allows_public_address(self):
		with requests_mock.Mocker() as mocker:
			mocker.get("http://93.184.216.34/", text="hello")
			response = safe_get("http://93.184.216.34/")
		self.assertEqual(response.text, "hello")

	def test_rejects_redirect_to_internal_address(self):
		with requests_mock.Mocker() as mocker:
			mocker.get("http://93.184.216.34/", status_code=302, headers={"Location": "http://169.254.169.254/"})
			with self.assertRaises(UnsafeUrlError):
				safe_get("http://93.184.216.34/")

	def test_rejects_oversize_body(self):
		with requests_mock.Mocker() as mocker:
			mocker.get("http://93.184.216.34/", content=b"x" * 2048)
			with self.assertRaises(UnsafeUrlError):
				safe_get("http://93.184.216.34/", max_bytes=1024)
