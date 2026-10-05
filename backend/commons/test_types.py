from django.core.exceptions import ValidationError
from django.test import SimpleTestCase

from commons.types import Email


class EmailTestCase(SimpleTestCase):
	def test_valid_address_constructs(self) -> None:
		self.assertEqual(Email("user@example.com"), "user@example.com")

	def test_value_is_stored_verbatim(self) -> None:
		self.assertEqual(Email("User.Name@Example.COM"), "User.Name@Example.COM")

	def test_invalid_address_raises(self) -> None:
		for value in ["", "not-an-email", "user@", "@example.com", "user@localhost@"]:
			with self.subTest(value=value), self.assertRaises(ValidationError):
				Email(value)

	def test_local_part_and_domain(self) -> None:
		email = Email("user.name@sub.example.com")
		self.assertEqual(email.local_part, "user.name")
		self.assertEqual(email.domain, "sub.example.com")

	def test_quoted_local_part_splits_on_last_at(self) -> None:
		email = Email('"a@b"@example.com')
		self.assertEqual(email.local_part, '"a@b"')
		self.assertEqual(email.domain, "example.com")

	def test_usable_where_str_is_expected(self) -> None:
		email = Email("user@example.com")
		self.assertIsInstance(email, str)
		self.assertEqual(email.lower(), "user@example.com")
		self.assertEqual("to: " + email, "to: user@example.com")
