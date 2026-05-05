"""Password reset codes - 6-digit, 30-minute expiry."""

from datetime import timedelta

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone
from django.utils.crypto import constant_time_compare, salted_hmac

_RESET_CODE_SALT = "accounts.password_reset_code"


class PasswordResetCode(models.Model):
	"""One-time code for password reset, emailed to the user."""

	user = models.ForeignKey(
		settings.AUTH_USER_MODEL,
		on_delete=models.CASCADE,
		related_name="password_reset_codes",
	)
	code_hash = models.CharField(max_length=64)
	created_at = models.DateTimeField(auto_now_add=True)

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
	def create_for_user(cls, *, user, code: str) -> PasswordResetCode:
		return cls.objects.create(user=user, code_hash=cls.hash_code(code))

	def matches_code(self, code: str) -> bool:
		try:
			candidate_hash = self.hash_code(code)
		except ValidationError:
			return False
		return constant_time_compare(self.code_hash, candidate_hash)

	@staticmethod
	def _validate_code(code: str) -> None:
		if len(code) != 6 or not code.isdigit():
			raise ValidationError("Password reset code must be exactly 6 digits.")

	@property
	def is_expired(self) -> bool:
		return timezone.now() - self.created_at > timedelta(minutes=30)
