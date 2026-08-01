"""Everything the opaque device-session credential does, minus HTTP.

The views own transports (cookie vs. bearer header, CSRF, Set-Cookie); this
module owns the token, the row, and the lifetime rules that decide whether a
row is still a session. Keeping the split sharp is what makes the auth class
and the endpoints small enough to read in one sitting.
"""

from __future__ import annotations

import hashlib
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta

from django.conf import settings
from django.db import transaction
from django.db.models import Q, QuerySet
from django.utils import timezone

from accounts.models import DeviceSession, User

# 32 bytes of urlsafe base64 → 43 characters, 256 bits of entropy. Guessing is
# not a threat model anyone has to think about again.
_TOKEN_BYTES = 32

# ``last_used_at`` is only used to decide idle expiry against a multi-day
# window, so writing it on every request would be pure write amplification on
# SQLite. One hour of staleness against a 14-day default is noise.
TOUCH_INTERVAL = timedelta(hours=1)

# Bounded growth: a user cannot accumulate an unbounded pile of live sessions,
# and the sessions list therefore needs no pagination.
MAX_LIVE_SESSIONS_PER_USER = 20

# How long a dead row is kept before the maintenance command deletes it. Long
# enough that "why was I signed out?" is still answerable, short enough that the
# table cannot grow without bound.
DEAD_SESSION_RETENTION = timedelta(days=30)


class SessionLoginAbortedError(Exception):
	"""The credential validated, but the account changed underneath the login.

	Raised inside the session-creation transaction when the user row no longer
	matches what the password check ran against — a concurrent password change,
	reset, or deactivation committed in between, and each of those revokes every
	session precisely so that no session outlives it.
	"""


@dataclass(frozen=True)
class IssuedSession:
	session: DeviceSession
	# The only time the raw token exists outside the client. Never logged, never
	# stored, never returned again.
	token: str


@dataclass(frozen=True)
class DeviceSessionCleanupResult:
	sessions_deleted: int


def idle_lifetime() -> timedelta:
	return timedelta(days=settings.SESSION_IDLE_LIFETIME_DAYS)


def absolute_lifetime() -> timedelta:
	return timedelta(days=settings.SESSION_ABSOLUTE_LIFETIME_DAYS)


def generate_token() -> str:
	return secrets.token_urlsafe(_TOKEN_BYTES)


def hash_token(raw_token: str) -> str:
	"""SHA-256 hex of the raw token.

	A fast unsalted hash is the right primitive here, unlike for passwords: the
	input is 256 bits of CSPRNG output, so there is no dictionary to run and no
	entropy for a KDF to stretch. It has to be deterministic because the hash is
	the lookup key.
	"""
	return hashlib.sha256(raw_token.encode("utf-8")).hexdigest()


def live_sessions(*, now: datetime | None = None) -> QuerySet[DeviceSession]:
	"""Sessions that can still authenticate a request, most recently used first.

	Live means all three of: not revoked, used inside the idle window, created
	inside the absolute window. Expiry is evaluated here rather than written to
	the row, so retuning a lifetime takes effect immediately and consistently.
	"""
	now = now or timezone.now()
	return DeviceSession.objects.filter(
		revoked_at__isnull=True,
		last_used_at__gt=now - idle_lifetime(),
		created_at__gt=now - absolute_lifetime(),
	).order_by("-last_used_at")


def live_sessions_for_user(user: User, *, now: datetime | None = None) -> QuerySet[DeviceSession]:
	return live_sessions(now=now).filter(user=user)


def session_for_token(
	raw_token: str,
	*,
	transport: str,
	now: datetime | None = None,
) -> DeviceSession | None:
	"""The live session this token addresses, presented through its own transport.

	Returns None for every failure — unknown, revoked, expired, wrong transport,
	inactive owner. Callers turn that into "no credential" or "rejected"
	according to how the credential was presented; this function does not know
	the difference and must not decide it.
	"""
	if not raw_token:
		return None

	now = now or timezone.now()
	session = (
		live_sessions(now=now).select_related("user").filter(token_hash=hash_token(raw_token), transport=transport)
	).first()
	if session is None:
		return None
	# A custom row authenticator gets none of ModelBackend's
	# ``user_can_authenticate`` protection for free, and User.delete() is a soft
	# delete that only flips is_active — so this check is the one thing standing
	# between a deleted account and a working session.
	if not session.user.is_active:
		return None
	return session


def touch(session: DeviceSession, *, now: datetime | None = None) -> None:
	"""Advance ``last_used_at``, damped to at most one write per TOUCH_INTERVAL.

	One conditional UPDATE rather than read-then-write: concurrent requests would
	otherwise each see a stale value, each decide a write is due, and defeat the
	damping — which on SQLite means serialised write transactions on every
	request burst.
	"""
	now = now or timezone.now()
	DeviceSession.objects.filter(pk=session.pk, last_used_at__lt=now - TOUCH_INTERVAL).update(last_used_at=now)


def create_session(
	*,
	user: User,
	transport: str,
	device_label: str,
	ip: str | None,
	user_agent: str,
	password_hash_at_login: str,
	replaces_token: str | None = None,
) -> IssuedSession:
	"""Issue a session, atomically with the checks that make it safe to issue.

	``password_hash_at_login`` is the ``user.password`` value the submitted
	credentials were verified against. The transaction re-reads the row and
	aborts if it changed or the account went inactive: a login validated against
	the old password must not commit a session *after* the password change that
	revoked everything, or the change would silently leave a live session behind.
	String equality, not a second KDF run — the stored hash is already the
	comparison key, and ``BEGIN IMMEDIATE`` guarantees the re-read observes any
	committed change.
	"""
	with transaction.atomic():
		fresh = User._base_manager.filter(pk=user.pk).values("password", "is_active").first()
		if fresh is None or not fresh["is_active"] or fresh["password"] != password_hash_at_login:
			raise SessionLoginAbortedError("The account changed while this login was being processed.")

		if replaces_token:
			revoke_session_for_token(replaces_token, reason=DeviceSession.RevokeReason.LOGIN_REPLACED)

		_evict_to_capacity(user, keeping_room_for=1)

		raw_token = generate_token()
		session = DeviceSession.objects.create(
			user=user,
			token_hash=hash_token(raw_token),
			transport=transport,
			device_label=device_label[:120],
			ip=ip or None,
			user_agent=user_agent[:256],
			last_used_at=timezone.now(),
		)

	return IssuedSession(session=session, token=raw_token)


def _evict_to_capacity(user: User, *, keeping_room_for: int) -> int:
	"""Revoke least-recently-used live sessions until there is room for more.

	Runs inside the caller's transaction. On SQLite ``BEGIN IMMEDIATE`` takes the
	write lock when the transaction opens, so concurrent logins serialise here
	rather than racing the count against the insert.
	"""
	live = live_sessions_for_user(user)
	surplus = live.count() + keeping_room_for - MAX_LIVE_SESSIONS_PER_USER
	if surplus <= 0:
		return 0

	# Slicing a queryset cannot be used directly in an UPDATE's WHERE clause on
	# every backend, so materialise the primary keys first.
	doomed = list(live.order_by("last_used_at").values_list("pk", flat=True)[:surplus])
	return DeviceSession.objects.filter(pk__in=doomed).update(
		revoked_at=timezone.now(),
		revoke_reason=DeviceSession.RevokeReason.CAPACITY_EVICTED,
	)


def revoke_session_for_token(raw_token: str, *, reason: str) -> bool:
	"""Revoke whatever live session this token addresses, whatever its transport.

	Deliberately transport-agnostic and user-agnostic: presenting the token is
	proof of holding it, and both callers (login replacement, logout) are acting
	on the credential in front of them rather than on an authenticated identity.
	"""
	if not raw_token:
		return False

	updated = (
		live_sessions()
		.filter(token_hash=hash_token(raw_token))
		.update(
			revoked_at=timezone.now(),
			revoke_reason=reason[:32],
		)
	)
	return updated > 0


def revoke_all_sessions_for_user(
	user: User,
	*,
	reason: str,
	except_session: DeviceSession | None = None,
	using: str | None = None,
) -> int:
	"""Revoke every live session owned by ``user``, optionally sparing one.

	Password *change* spares the caller's own session — it just proved it knows
	the current password, and the account screen promises it stays signed in.
	Password *reset*, deactivation and the recovery command spare nothing,
	because they exist for the case where the credential may be in the wrong
	hands. Already-dead rows are untouched so their reason and timestamp survive.
	"""
	manager = DeviceSession.objects.using(using) if using is not None else DeviceSession.objects
	sessions = manager.filter(user=user, revoked_at__isnull=True)
	if except_session is not None:
		sessions = sessions.exclude(pk=except_session.pk)
	return sessions.update(revoked_at=timezone.now(), revoke_reason=reason[:32])


def cleanup_device_sessions(*, now: datetime | None = None) -> DeviceSessionCleanupResult:
	"""Delete rows that have been dead for longer than DEAD_SESSION_RETENTION.

	Dead means revoked, idle-expired, or past the absolute lifetime; the
	retention window is measured from whichever of those happened.
	"""
	now = now or timezone.now()
	dead = DeviceSession.objects.filter(
		Q(revoked_at__lt=now - DEAD_SESSION_RETENTION)
		| Q(revoked_at__isnull=True, last_used_at__lt=now - idle_lifetime() - DEAD_SESSION_RETENTION)
		| Q(revoked_at__isnull=True, created_at__lt=now - absolute_lifetime() - DEAD_SESSION_RETENTION)
	)
	sessions_deleted, _ = dead.delete()
	return DeviceSessionCleanupResult(sessions_deleted=sessions_deleted)
