from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, cast
from uuid import UUID

from django.conf import settings
from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework.request import Request
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import AccessToken, RefreshToken

from accounts.models import RefreshSessionFamily, RefreshTokenRecord, User
from commons.network import client_ip

REFRESH_FAMILY_CLAIM = "family_id"
REFRESH_REQUEST_HEADER = "HTTP_X_REFRESH_REQUEST"
REFRESH_REQUEST_HEADER_VALUE = "1"


@dataclass(frozen=True)
class IssuedTokens:
	access: str
	refresh: str | None = None


@dataclass(frozen=True)
class RotatedRefreshTokens:
	access: str
	refresh: str


@dataclass(frozen=True)
class RefreshSessionCleanupResult:
	families_deleted: int
	token_records_deleted: int


class RefreshSessionError(Exception):
	"""The refresh token cannot be used for an authenticated session."""


class RefreshTokenReuseError(RefreshSessionError):
	"""A refresh token record was presented after it had already been used."""


def issue_tokens_for_login(
	*,
	user: User,
	remember_me: bool,
	request: Request,
) -> IssuedTokens:
	if not remember_me:
		return IssuedTokens(access=str(AccessToken.for_user(user)))

	now = timezone.now()
	with transaction.atomic():
		family = RefreshSessionFamily.objects.create(
			user=user,
			last_used_at=now,
			device_label=_device_label(request),
			ip=client_ip(request) or None,
			user_agent=_user_agent(request),
		)
		refresh = RefreshToken.for_user(user)
		refresh[REFRESH_FAMILY_CLAIM] = str(family.family_id)
		RefreshTokenRecord.objects.create(
			family=family,
			jti=_token_jti(refresh),
			issued_at=now,
		)

	return IssuedTokens(access=str(refresh.access_token), refresh=str(refresh))


def rotate_refresh_token(raw_refresh_token: str) -> RotatedRefreshTokens:
	refresh = _decode_refresh_token(raw_refresh_token)
	family_uuid = _token_family_id(refresh)
	jti = _token_jti(refresh)
	now = timezone.now()

	with transaction.atomic():
		try:
			family = RefreshSessionFamily.objects.select_for_update().select_related("user").get(family_id=family_uuid)
		except RefreshSessionFamily.DoesNotExist as exc:
			raise RefreshSessionError("Refresh session family does not exist.") from exc

		if family.is_revoked:
			raise RefreshSessionError("Refresh session family has been revoked.")

		rejection: RefreshSessionError | None = None
		next_refresh: RefreshToken | None = None
		try:
			record = RefreshTokenRecord.objects.select_for_update().get(family=family, jti=jti)
		except RefreshTokenRecord.DoesNotExist as exc:
			family.revoke(RefreshSessionFamily.RevokeReason.UNKNOWN_TOKEN)
			rejection = RefreshSessionError("Refresh token is not part of this session family.")
			rejection.__cause__ = exc
		else:
			updated = RefreshTokenRecord.objects.filter(pk=record.pk, used_at__isnull=True).update(used_at=now)
			if updated == 0:
				family.revoke(RefreshSessionFamily.RevokeReason.REUSE)
				rejection = RefreshTokenReuseError("Refresh token has already been used.")
			else:
				family.last_used_at = now
				family.save(update_fields=["last_used_at"])

				next_refresh = RefreshToken.for_user(family.user)
				next_refresh[REFRESH_FAMILY_CLAIM] = str(family.family_id)
				RefreshTokenRecord.objects.create(
					family=family,
					jti=_token_jti(next_refresh),
					parent_jti=record.jti,
					issued_at=now,
				)

	if rejection is not None:
		raise rejection
	if next_refresh is None:
		raise RefreshSessionError("Refresh token rotation did not issue a replacement token.")

	return RotatedRefreshTokens(access=str(next_refresh.access_token), refresh=str(next_refresh))


def revoke_refresh_family_for_token(raw_refresh_token: str, *, reason: str) -> bool:
	try:
		refresh = _decode_refresh_token(raw_refresh_token)
		family_uuid = _token_family_id(refresh)
	except RefreshSessionError:
		return False

	with transaction.atomic():
		family = RefreshSessionFamily.objects.select_for_update().filter(family_id=family_uuid).first()
		if family is None:
			return False
		family.revoke(reason)
	return True


def cleanup_refresh_sessions(*, now: datetime | None = None) -> RefreshSessionCleanupResult:
	now = now or timezone.now()
	cutoff = now - _refresh_token_lifetime()
	expired_families = RefreshSessionFamily.objects.filter(
		Q(revoked_at__isnull=False, revoked_at__lt=cutoff) | Q(revoked_at__isnull=True, last_used_at__lt=cutoff)
	)
	families_deleted = expired_families.count()
	expired_families.delete()
	token_records_deleted, _ = RefreshTokenRecord.objects.filter(
		used_at__isnull=False,
		used_at__lt=cutoff,
	).delete()
	return RefreshSessionCleanupResult(
		families_deleted=families_deleted,
		token_records_deleted=token_records_deleted,
	)


def refresh_lifetime_seconds() -> int:
	return int(_refresh_token_lifetime().total_seconds())


def _decode_refresh_token(raw_refresh_token: str) -> RefreshToken:
	if not raw_refresh_token:
		raise RefreshSessionError("Refresh token is missing.")
	try:
		return RefreshToken(cast(Any, raw_refresh_token))
	except TokenError as exc:
		raise RefreshSessionError(str(exc)) from exc


def _token_family_id(refresh: RefreshToken) -> UUID:
	raw = refresh.get(REFRESH_FAMILY_CLAIM)
	if not isinstance(raw, str):
		raise RefreshSessionError("Refresh token is missing its session family claim.")
	try:
		return UUID(raw)
	except ValueError as exc:
		raise RefreshSessionError("Refresh token has an invalid session family claim.") from exc


def _token_jti(refresh: RefreshToken) -> str:
	raw = refresh.get("jti")
	if not isinstance(raw, str) or not raw:
		raise RefreshSessionError("Refresh token is missing its jti claim.")
	if len(raw) > 64:
		raise RefreshSessionError("Refresh token jti is too long.")
	return raw


def _refresh_token_lifetime() -> timedelta:
	return cast(timedelta, settings.SIMPLE_JWT["REFRESH_TOKEN_LIFETIME"])


def _device_label(request: Request) -> str:
	raw = request.data.get("device_label") if isinstance(request.data, dict) else None
	if not isinstance(raw, str):
		return ""
	return raw.strip()[:120]


def _user_agent(request: Request) -> str:
	return str(request.META.get("HTTP_USER_AGENT", ""))[:500]
