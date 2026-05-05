"""Password reset codes: 6-digit, single-use, short-lived."""

from __future__ import annotations

from datetime import timedelta

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone
from django.utils.crypto import constant_time_compare, salted_hmac

PASSWORD_RESET_CODE_TTL = timedelta(minutes=30)
PASSWORD_RESET_CODE_MAX_ATTEMPTS = 5
_RESET_CODE_SALT = "accounts.password_reset_code"


class PasswordResetCode(models.Model):
	"""One-time password reset code metadata.

	The raw 6-digit code is only sent to the user. At rest we store an HMAC so
	a database leak does not immediately expose usable reset codes.
	"""

	user = models.ForeignKey(
		settings.AUTH_USER_MODEL,
		on_delete=models.CASCADE,
		related_name="password_reset_codes",
	)
	code_hash = models.CharField(max_length=64)
	created_at = models.DateTimeField(auto_now_add=True)
	failed_attempts = models.PositiveSmallIntegerField(default=0)

	class Meta:
		indexes = [
			models.Index(fields=["user", "created_at"]),
			models.Index(fields=["code_hash", "created_at"]),
		]

	def __str__(self) -> str:
		return f"ResetCode(user={self.user_id}, created_at={self.created_at}, code_hash={self.code_hash[:8]})"

	@classmethod
	def hash_code(cls, code: str) -> str:
		cls._validate_code(code)
		return salted_hmac(_RESET_CODE_SALT, code, secret=settings.SECRET_KEY, algorithm="sha256").hexdigest()

	@classmethod
	def create_for_user(cls, *, user: models.Model, code: str) -> PasswordResetCode:
		return cls.objects.create(user=user, code_hash=cls.hash_code(code))

	@classmethod
	def issue_for_user(cls, *, user: models.Model, code: str) -> PasswordResetCode:
		cls.objects.filter(user=user).delete()
		return cls.create_for_user(user=user, code=code)

	@property
	def is_expired(self) -> bool:
		return timezone.now() - self.created_at > PASSWORD_RESET_CODE_TTL

	@property
	def is_locked(self) -> bool:
		return self.failed_attempts >= PASSWORD_RESET_CODE_MAX_ATTEMPTS

	def check_code(self, code: str) -> bool:
		if self.is_expired or self.is_locked:
			return False
		try:
			candidate_hash = self.hash_code(code)
		except ValidationError:
			return False
		return constant_time_compare(self.code_hash, candidate_hash)

	def record_failure(self) -> None:
		if self.is_expired or self.is_locked:
			return
		self.failed_attempts += 1
		self.save(update_fields=["failed_attempts"])

	@staticmethod
	def _validate_code(code: str) -> None:
		if len(code) != 6 or not code.isascii() or not code.isdigit():
			raise ValidationError("Password reset code must be exactly 6 ASCII digits.")
