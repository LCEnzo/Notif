from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, cast
from uuid import UUID

from django.conf import settings
from django.db import transaction
from django.db.models import Q, QuerySet
from django.utils import timezone
from rest_framework.request import Request
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import AccessToken, RefreshToken

from accounts.models import RefreshSessionFamily, RefreshTokenRecord, User

REFRESH_FAMILY_CLAIM = "family_id"
REFRESH_JTI_CLAIM = "jti"
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
			ip=_client_ip(request) or None,
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

		# Rejections that also write (a revoke) must not raise inside the atomic
		# block, or the rollback would undo the revoke. Stash and raise afterwards.
		rejection: RefreshSessionError | None = None
		next_refresh: RefreshToken | None = None

		if now - family.created_at > _refresh_absolute_lifetime():
			family.revoke(RefreshSessionFamily.RevokeReason.MAX_LIFETIME)
			rejection = RefreshSessionError("Refresh session has reached its maximum lifetime.")
		else:
			try:
				record = RefreshTokenRecord.objects.select_for_update().get(family=family, jti=jti)
			except RefreshTokenRecord.DoesNotExist as exc:
				family.revoke(RefreshSessionFamily.RevokeReason.UNKNOWN_TOKEN)
				rejection = RefreshSessionError("Refresh token is not part of this session family.")
				rejection.__cause__ = exc
			else:
				updated = RefreshTokenRecord.objects.filter(pk=record.pk, used_at__isnull=True).update(used_at=now)
				if updated == 0:
					live_child = _replayable_child(family, record, now=now)
					if live_child is None:
						family.revoke(RefreshSessionFamily.RevokeReason.REUSE)
						rejection = RefreshTokenReuseError("Refresh token has already been used.")
					else:
						_touch_family(family, now)
						next_refresh = _token_for_record(family, live_child)
				else:
					_touch_family(family, now)
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


def _replayable_child(
	family: RefreshSessionFamily,
	record: RefreshTokenRecord,
	*,
	now: datetime,
) -> RefreshTokenRecord | None:
	"""The still-unused child of an already-used ``record``, if the replay is benign.

	Strict single-use rotation causes spurious full logouts in two situations that
	have nothing to do with theft:

	1. Browser session restore cold-starts several tabs at once and they all
	present the same cookie before any of them has seen a rotated one.
	2. A rotation commits server-side but its response never reaches the client
	(a container recreated mid-deploy), so the client retries with the old jti.

	Neither is distinguishable from theft *in general*, so the replay is only
	forgiven when both hold: it happened inside ``JWT_REFRESH_ROTATION_GRACE``, and
	the presented token is the direct parent of the token that is currently live.
	A replay of any older ancestor, or of a parent whose child has itself already
	been rotated away, returns ``None`` and the caller revokes the family — theft
	detection is unchanged outside the window.
	"""
	used_at = record.used_at
	if used_at is None or now - used_at > _rotation_grace_period():
		return None

	return (
		RefreshTokenRecord.objects.select_for_update()
		.filter(family=family, parent_jti=record.jti, used_at__isnull=True)
		.first()
	)


def _token_for_record(family: RefreshSessionFamily, record: RefreshTokenRecord) -> RefreshToken:
	"""Rebuild a refresh token that maps onto an existing, still-unused record.

	Only the jti is persisted, not the token, so the replacement is minted fresh and
	pinned to the stored jti. That keeps single-use accounting intact — the reissued
	token and the original child are the same record — at the cost of pushing the
	token's own ``exp`` out to a full REFRESH_TOKEN_LIFETIME again, which stays
	bounded by JWT_REFRESH_ABSOLUTE_LIFETIME.
	"""
	token = RefreshToken.for_user(family.user)
	token[REFRESH_FAMILY_CLAIM] = str(family.family_id)
	token[REFRESH_JTI_CLAIM] = record.jti
	return token


def _touch_family(family: RefreshSessionFamily, now: datetime) -> None:
	family.last_used_at = now
	family.save(update_fields=["last_used_at"])


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


def revoke_all_refresh_families_for_user(user: User, *, reason: str) -> int:
	"""Revoke every currently-active refresh session family owned by ``user``.

	Used when a credential change should evict all outstanding sessions (password
	change/reset). Returns the number of families revoked. Already-revoked
	families are left untouched so their original reason/timestamp is preserved.
	"""
	return RefreshSessionFamily.objects.filter(user=user, revoked_at__isnull=True).update(
		revoked_at=timezone.now(),
		revoked_reason=reason[:80],
	)


def active_refresh_families_for_user(user: User) -> QuerySet[RefreshSessionFamily]:
	"""Families that could still mint an access token, newest activity first.

	"Active" means all three of: not revoked, used recently enough that its newest
	refresh token has not expired, and still inside the absolute session cap. The
	staleness and cap filters matter for the session list — a family last used four
	days ago is dead in practice (REFRESH_TOKEN_LIFETIME is 72h) and showing it as a
	live device would be a lie.
	"""
	now = timezone.now()
	return RefreshSessionFamily.objects.filter(
		user=user,
		revoked_at__isnull=True,
		last_used_at__gte=now - _refresh_token_lifetime(),
		created_at__gte=now - _refresh_absolute_lifetime(),
	).order_by("-last_used_at")


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
	raw = refresh.get(REFRESH_JTI_CLAIM)
	if not isinstance(raw, str) or not raw:
		raise RefreshSessionError("Refresh token is missing its jti claim.")
	if len(raw) > 64:
		raise RefreshSessionError("Refresh token jti is too long.")
	return raw


def _refresh_token_lifetime() -> timedelta:
	return cast(timedelta, settings.SIMPLE_JWT["REFRESH_TOKEN_LIFETIME"])


def _rotation_grace_period() -> timedelta:
	return settings.JWT_REFRESH_ROTATION_GRACE


def _refresh_absolute_lifetime() -> timedelta:
	return settings.JWT_REFRESH_ABSOLUTE_LIFETIME


def _device_label(request: Request) -> str:
	raw = request.data.get("device_label") if isinstance(request.data, dict) else None
	if not isinstance(raw, str):
		return ""
	return raw.strip()[:120]


def _user_agent(request: Request) -> str:
	return str(request.META.get("HTTP_USER_AGENT", ""))[:500]


def _client_ip(request: Request) -> str:
	forwarded = request.META.get("HTTP_X_FORWARDED_FOR", "")
	if forwarded:
		return forwarded.split(",", maxsplit=1)[0].strip()
	return str(request.META.get("REMOTE_ADDR", ""))
