"""Password reset codes — 6-digit, 30-minute expiry."""

from datetime import timedelta

from django.conf import settings
from django.db import models
from django.utils import timezone


class PasswordResetCode(models.Model):
	"""One-time code for password reset, emailed to the user."""

	user = models.ForeignKey(
		settings.AUTH_USER_MODEL,
		on_delete=models.CASCADE,
		related_name="password_reset_codes",
	)
	code = models.CharField(max_length=6)
	created_at = models.DateTimeField(auto_now_add=True)

	class Meta:
		indexes = [
			models.Index(fields=["user", "created_at"]),
			models.Index(fields=["code", "created_at"]),
		]

	def __str__(self) -> str:
		return f"ResetCode(user={self.user_id}, code={self.code})"

	@property
	def is_expired(self) -> bool:
		return timezone.now() - self.created_at > timedelta(minutes=30)
