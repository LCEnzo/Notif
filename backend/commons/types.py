"""Shared value types, validated at construction."""

from typing import Self

from django.core.validators import validate_email


class Email(str):
	"""A validated email address.

	Invariant: every instance passed ``django.core.validators.validate_email``
	(the same validator DRF's ``EmailField`` uses) at construction, so holding
	an ``Email`` is proof the string is a well-formed address. Construction
	raises Django's ``ValidationError`` otherwise. The value is stored as-is:
	no stripping, lowercasing, or other normalization.
	"""

	__slots__ = ()

	def __new__(cls, value: str) -> Self:
		validate_email(value)
		return super().__new__(cls, value)

	@property
	def local_part(self) -> str:
		"""Everything before the last ``@``."""
		return self.rpartition("@")[0]

	@property
	def domain(self) -> str:
		"""Everything after the last ``@``."""
		return self.rpartition("@")[2]
