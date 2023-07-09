import string
from math import log2

from django.core.exceptions import ValidationError

# Calculate the minimum entropy required by default
time_in_seconds = 100 * 365 * 24 * 60 * 60  # 100 years in seconds
attempts_per_second = 10**9  # Estimated attempts per second for a consumer CPU
efficiency_of_attack = 1  # Efficiency of the brute-force attack
E_min = log2(time_in_seconds * attempts_per_second * efficiency_of_attack)


class EntropyValidator:
	def __init__(self, min_entropy=E_min):
		self.min_entropy = min_entropy

	def validate(self, password, user=None):
		password_entropy = self.calculate_password_entropy(password)
		if password_entropy < self.min_entropy:
			raise ValidationError(
				self.get_help_text(password_entropy=password_entropy),
				code="insufficient_entropy",
			)

	def get_help_text(self, password_entropy=None):
		password_string = (
			""
			if password_entropy is None
			else f"Your password has {password_entropy} bits of entropy. "
		)

		return (
			f"The password entropy must be at least {self.min_entropy} bits. "
			+ f"{password_string}" 
			+ "Try increasing the number of characters, as well as using at least one "
			+ "digit, lower and upper case letter, and symbol."
		)

	def calculate_password_entropy(self, password: str) -> float:
		has_digit = any(c.isdigit() for c in password)
		has_lower = any(c.islower() for c in password)
		has_upper = any(c.isupper() for c in password)
		has_punct = any(c in string.punctuation for c in password)
		has_other = any(
			c not in string.digits + string.ascii_letters + string.punctuation
			for c in password
		)

		categories = [has_digit, has_lower, has_upper, has_punct, has_other]
		lengths = [10, 26, 26, len(string.punctuation), 40]
		char_set = sum(
			cat * length if cat else 0 for cat, length in zip(categories, lengths, strict=True)
		)

		password_entropy = log2(char_set) * len(password)

		return password_entropy

# Instantiate the validator
entropy_validator = EntropyValidator()
