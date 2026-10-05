from types import SimpleNamespace
from typing import cast
from unittest.mock import patch

import pytest
from django.core import mail
from django.core.mail import EmailMultiAlternatives
from django.test import TestCase
from hypothesis import given, settings
from hypothesis import strategies as st
from rest_framework.test import APIRequestFactory

from accounts.models import User
from commons.email import send_password_reset_email
from commons.permissions import IsRequestingThemselves

_REQUESTER_PK = 7


def _requesting_themselves(raw_pk: str) -> bool:
	request = APIRequestFactory().put("/")
	request.user = User(pk=_REQUESTER_PK)
	return IsRequestingThemselves().has_permission(request, SimpleNamespace(kwargs={"pk": raw_pk}))


def test_is_requesting_themselves_grants_only_the_requesters_own_id():
	assert _requesting_themselves(str(_REQUESTER_PK))
	for raw_pk in (
		str(_REQUESTER_PK + 1),
		str(-_REQUESTER_PK),
		f"{_REQUESTER_PK}x",
		"abc",
		"\N{SUPERSCRIPT TWO}",
		"1" * 5000,
	):
		assert not _requesting_themselves(raw_pk), raw_pk


# Path segments the router can hand over: anything but "/" and ".". Biased toward
# the near misses: numerals in every Unicode digit script, signs, padding and
# separators around the requester's own id, and digit runs past int()'s limit.
_path_segments = st.one_of(
	st.text(alphabet=st.characters(exclude_characters="/."), min_size=1, max_size=20),
	st.text(alphabet=st.characters(categories=["Nd", "No"]), min_size=1, max_size=6),
	st.builds(
		"{}{}{}".format,
		st.sampled_from(["", " ", "+", "-", "0", "00", "_"]),
		st.sampled_from(
			[str(_REQUESTER_PK), str(_REQUESTER_PK + 1), "\N{ARABIC-INDIC DIGIT SEVEN}", "\N{SUPERSCRIPT TWO}"]
		),
		st.sampled_from(["", " ", "_", "0", "x", "e3"]),
	),
	st.integers(min_value=4290, max_value=4310).map(lambda length: "1" * length),
)


@pytest.mark.property
@given(raw_pk=_path_segments)
@settings(max_examples=300)
def test_is_requesting_themselves_is_total_and_keeps_its_integer_reading(raw_pk: str):
	# The permission never raises: whatever int() reads keeps its integer
	# answer, and whatever it cannot read is refused.
	try:
		expected = int(raw_pk) == _REQUESTER_PK
	except ValueError:
		expected = False

	assert _requesting_themselves(raw_pk) is expected


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
