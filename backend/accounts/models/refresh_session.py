from __future__ import annotations

import uuid
from typing import Any

from django.conf import settings
from django.db import models
from django.utils import timezone


class RefreshSessionFamily(models.Model):
	class RevokeReason(models.TextChoices):
		LOGOUT = "logout", "Logout"
		REUSE = "reuse", "Refresh token reuse"
		UNKNOWN_TOKEN = "unknown_token", "Unknown refresh token"
		EXPIRED = "expired", "Expired"
		LOGIN_REPLACED = "login_replaced", "Replaced by a new login"

	user = models.ForeignKey(
		settings.AUTH_USER_MODEL,
		on_delete=models.CASCADE,
		related_name="refresh_session_families",
	)
	family_id = models.UUIDField(default=uuid.uuid4, unique=True, editable=False, db_index=True)
	created_at = models.DateTimeField(auto_now_add=True)
	last_used_at = models.DateTimeField(default=timezone.now, db_index=True)
	revoked_at = models.DateTimeField(null=True, blank=True, db_index=True)
	revoked_reason = models.CharField(max_length=80, blank=True)
	device_label = models.CharField(max_length=120, blank=True)
	ip = models.GenericIPAddressField(null=True, blank=True)
	user_agent = models.CharField(max_length=500, blank=True)

	class Meta:
		indexes = [
			models.Index(fields=["user", "-last_used_at"], name="accounts_rsf_user_last_used_idx"),
			models.Index(fields=["revoked_at", "last_used_at"], name="accounts_rsf_gc_idx"),
		]

	def __str__(self) -> str:
		return f"RefreshSessionFamily({self.family_id}, user={self.user_id})"

	@property
	def is_revoked(self) -> bool:
		return self.revoked_at is not None

	def revoke(self, reason: str, *, save: bool = True) -> None:
		if self.revoked_at is None:
			self.revoked_at = timezone.now()
		self.revoked_reason = reason[:80]
		if save:
			self.save(update_fields=["revoked_at", "revoked_reason"])


class RefreshTokenRecord(models.Model):
	family = models.ForeignKey(RefreshSessionFamily, on_delete=models.CASCADE, related_name="tokens")
	jti = models.CharField(max_length=64, unique=True, db_index=True)
	parent_jti = models.CharField(max_length=64, blank=True, db_index=True)
	issued_at = models.DateTimeField(default=timezone.now)
	used_at = models.DateTimeField(null=True, blank=True, db_index=True)

	class Meta:
		indexes = [
			models.Index(fields=["family", "jti"], name="accounts_rtr_family_jti_idx"),
			models.Index(fields=["family", "used_at"], name="accounts_rtr_family_used_idx"),
		]

	def __str__(self) -> str:
		return f"RefreshTokenRecord({self.jti}, family={self.family_id})"

	def save(self, *args: Any, **kwargs: Any) -> None:
		if len(self.jti) > 64:
			raise ValueError("Refresh token jti exceeds 64 characters")
		if len(self.parent_jti) > 64:
			raise ValueError("Parent refresh token jti exceeds 64 characters")
		super().save(*args, **kwargs)

	def mark_used(self, *, save: bool = True) -> None:
		if self.used_at is None:
			self.used_at = timezone.now()
		if save:
			self.save(update_fields=["used_at"])
