from __future__ import annotations

import uuid

from django.conf import settings
from django.db import models
from django.utils import timezone


class DeviceSession(models.Model):
	"""One signed-in device, addressed by an opaque token whose hash lives here.

	There is exactly one row per session and exactly one transport per row. The
	raw token is shown once at login and never stored; ``token_hash`` is the only
	server-side representation of it.

	Expiry is derived, not stored: see ``accounts.device_sessions.live_sessions``.
	Columns holding a computed deadline would have to be migrated every time a
	lifetime is retuned, and would disagree with the config the moment they did.
	"""

	class Transport(models.TextChoices):
		COOKIE = "cookie", "Cookie"
		BEARER = "bearer", "Bearer"

	class RevokeReason(models.TextChoices):
		LOGOUT = "logout", "Logout"
		REVOKED_BY_USER = "revoked_by_user", "Revoked by the account owner"
		# An enum label, not a credential.
		PASSWORD_CHANGE = "password_change", "Password changed or reset"  # pragma: allowlist secret
		LOGIN_REPLACED = "login_replaced", "Replaced by a new login"
		CAPACITY_EVICTED = "capacity_evicted", "Evicted by the per-user session cap"
		USER_DEACTIVATED = "user_deactivated", "Owning account was deactivated"

	user = models.ForeignKey(
		settings.AUTH_USER_MODEL,
		on_delete=models.CASCADE,
		related_name="device_sessions",
	)
	public_id = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
	# SHA-256 hex. unique=True already builds the index the auth path looks up on.
	token_hash = models.CharField(max_length=64, unique=True)
	transport = models.CharField(max_length=16, choices=Transport.choices)
	device_label = models.CharField(max_length=120, blank=True)
	ip = models.GenericIPAddressField(null=True, blank=True)
	user_agent = models.CharField(max_length=256, blank=True)
	created_at = models.DateTimeField(auto_now_add=True)
	last_used_at = models.DateTimeField(default=timezone.now, db_index=True)
	revoked_at = models.DateTimeField(null=True, blank=True, db_index=True)
	revoke_reason = models.CharField(max_length=32, blank=True)

	class Meta:
		indexes = [
			models.Index(fields=["user", "-last_used_at"], name="accounts_ds_user_lastused_idx"),
			models.Index(fields=["revoked_at", "last_used_at"], name="accounts_ds_gc_idx"),
		]

	def __str__(self) -> str:
		return f"DeviceSession({self.public_id}, user={self.user_id}, transport={self.transport})"

	@property
	def is_revoked(self) -> bool:
		return self.revoked_at is not None

	def revoke(self, reason: str, *, save: bool = True) -> None:
		"""Mark this session dead, preserving the first revocation's timestamp.

		Re-revoking keeps the original ``revoked_at`` so the audit trail says when
		the session actually stopped working, not when someone last asked again.
		"""
		if self.revoked_at is None:
			self.revoked_at = timezone.now()
		self.revoke_reason = reason[:32]
		if save:
			self.save(update_fields=["revoked_at", "revoke_reason"])
