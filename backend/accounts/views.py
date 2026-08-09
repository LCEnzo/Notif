import contextlib
import hashlib
import logging
import threading
from collections.abc import Callable, Sequence
from datetime import timedelta
from typing import TYPE_CHECKING, Any, Literal, cast

from django.conf import settings
from django.contrib.auth import authenticate
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.db.models.query import QuerySet
from django.middleware.csrf import rotate_token
from django.utils import timezone
from drf_spectacular.utils import OpenApiResponse, extend_schema, extend_schema_view
from rest_framework import status
from rest_framework.authentication import SessionAuthentication, get_authorization_header
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.mixins import ListModelMixin
from rest_framework.parsers import JSONParser
from rest_framework.permissions import AllowAny, IsAdminUser, IsAuthenticated
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.serializers import BaseSerializer
from rest_framework.throttling import BaseThrottle, ScopedRateThrottle, UserRateThrottle
from rest_framework.views import APIView
from rest_framework.viewsets import GenericViewSet, ModelViewSet

from accounts.authentication import AUTH_SCHEME
from accounts.device_sessions import (
	SessionLoginAbortedError,
	absolute_lifetime,
	create_session,
	live_sessions_for_user,
	revoke_all_sessions_for_user,
	revoke_session_for_token,
	session_for_token,
)
from accounts.models import DeviceSession, User
from accounts.models.password_reset import PasswordResetBudget
from accounts.serializers import (
	DeviceSessionSerializer,
	LoginRequestSerializer,
	LoginResponseSerializer,
	PasswordResetConfirmSerializer,
	PasswordResetRequestSerializer,
	SessionRevokeResponseSerializer,
	StatusResponseSerializer,
	UserCreationSerializer,
	UserFullReadSerializer,
	UserMinimalReadSerializer,
)
from commons.network import client_ip
from commons.permissions import IsRequestingThemselves, ReadOnly
from commons.types import Email

if TYPE_CHECKING:
	_UserModelViewSet = ModelViewSet[User]
	_DeviceSessionGenericViewSet = GenericViewSet[DeviceSession]
else:
	_UserModelViewSet = ModelViewSet
	_DeviceSessionGenericViewSet = GenericViewSet

logger = logging.getLogger(__name__)

SessionCookieSameSite = Literal["Lax", "Strict", "None", False]

# ── password-reset per-email budgets ────────────────────────────
# The reset code is 6 digits and the on-disk lockout (5 failures) resets every
# time a new code is minted, so without a budget that survives code refresh an
# attacker rotating IPs could grind the 10^6 space. These budgets key on the
# *email*, not the IP, which also caps cross-site form POSTs from victims'
# browsers. Database-backed (see PasswordResetBudget) so the limits are shared
# across all gunicorn workers and survive worker recycling; both counters share
# one fixed window, reset together on first use after the window elapses.
_PASSWORD_RESET_REQUEST_BUDGET = (5, 60 * 60)  # (mints per hour, window seconds)
_PASSWORD_RESET_CONFIRM_BUDGET = (10, 60 * 60)  # (guesses per hour, window seconds)

BudgetKind = Literal["request", "confirm"]


def _email_budget_allows(kind: BudgetKind, email: Email, limit: int, window_seconds: int) -> bool:
	"""True when this email may still perform a password-reset action.

	The email is stored hashed so plaintext addresses never hit the database.
	The window opens on first use after the previous window elapsed and is
	shared by both counters, so its expiry zeroes both; each allowed use
	increments the matching counter under a row lock, so concurrent requests
	(and multiple gunicorn workers) share one budget.
	"""
	field = "mint_count" if kind == "request" else "guess_count"
	email_hash = hashlib.sha256(email.lower().encode()).hexdigest()
	now = timezone.now()
	with transaction.atomic():
		row, _ = PasswordResetBudget.objects.select_for_update().get_or_create(
			email_hash=email_hash,
			defaults={"window_started_at": now},
		)
		if row.window_started_at < now - timedelta(seconds=window_seconds):
			row.window_started_at = now
			row.mint_count = 0
			row.guess_count = 0
		if getattr(row, field) >= limit:
			return False
		setattr(row, field, getattr(row, field) + 1)
		row.save(update_fields=["mint_count", "guess_count", "window_started_at"])
		return True


def _send_reset_email_in_background(to_email: Email, code: str) -> None:
	"""Send a reset email off the request thread.

	The SMTP round-trip only happens for existing accounts; doing it inline
	made wall-clock time an account-existence oracle on the reset endpoint.
	Bounded: the per-IP throttle (3/min) and the per-email budget (5/hour)
	above cap how many of these threads can ever exist.
	"""
	# Imported at call time so tests can patch commons.email.send_password_reset_email.
	from commons.email import send_password_reset_email

	# send_password_reset_email already logs failures with the address attached;
	# the daemon thread must not die with a traceback.
	with contextlib.suppress(Exception):
		send_password_reset_email(to_email, code)


def _spawn_reset_email_thread(to_email: Email, code: str) -> None:
	threading.Thread(
		target=_send_reset_email_in_background,
		args=(to_email, code),
		daemon=True,
	).start()


# Module-level seam: tests monkeypatch this with the synchronous sender.
_send_reset_email: Callable[[Email, str], None] = _spawn_reset_email_thread


class AuthThrottleMixin:
	"""Disables throttling in tests; applies UserRateThrottle + ScopedRateThrottle otherwise.

	Subclasses must set throttle_scope so ScopedRateThrottle picks up the right rate.
	"""

	throttle_scope: str

	def get_throttles(self) -> list[BaseThrottle]:
		if settings.TESTING:
			return []
		return [UserRateThrottle(), ScopedRateThrottle()]


# ── request gates and cookie plumbing ────────────────────────


def _is_json_content_type(request: Request) -> bool:
	media_type = (request.content_type or "").split(";", 1)[0].strip().lower()
	return media_type == "application/json"


def _require_json_request(request: Request) -> None:
	"""Reject anything a cross-site HTML form could have produced.

	DRF marks its views ``csrf_exempt`` and the auth endpoints clear
	``authentication_classes``, so without this gate a top-level form POST from
	any site would be a CORS *simple request*: no preflight, no CSRF token, and
	the browser applies whatever ``Set-Cookie`` comes back. On login that plants
	the attacker's session in the victim's browser; on logout it drops a session
	the caller never held.

	A form can only send ``application/x-www-form-urlencoded``,
	``multipart/form-data`` or ``text/plain``, so a JSON content type proves the
	request was not one — and makes any cross-origin attempt preflight, which
	CORS then refuses. ``parser_classes = [JSONParser]`` on these views makes it
	structural rather than advisory: a form-encoded body cannot be parsed at all.
	"""
	if _is_json_content_type(request):
		return
	raise ValidationError(
		{
			"content_type": (
				"Send a JSON request body. Form-encoded requests are rejected because a "
				"cross-site form could forge them."
			)
		}
	)


def _session_cookie_samesite() -> SessionCookieSameSite:
	return cast(SessionCookieSameSite, settings.SESSION_TOKEN_COOKIE_SAMESITE)


def _set_session_cookie(response: Response, raw_token: str) -> None:
	response.set_cookie(
		settings.SESSION_TOKEN_COOKIE_NAME,
		raw_token,
		max_age=int(absolute_lifetime().total_seconds()),
		path=settings.SESSION_TOKEN_COOKIE_PATH,
		secure=settings.SESSION_TOKEN_COOKIE_SECURE,
		httponly=True,
		samesite=_session_cookie_samesite(),
	)


def _clear_session_cookie(response: Response) -> None:
	response.delete_cookie(
		settings.SESSION_TOKEN_COOKIE_NAME,
		path=settings.SESSION_TOKEN_COOKIE_PATH,
		samesite=_session_cookie_samesite(),
	)


def _clear_legacy_refresh_cookie(response: Response) -> None:
	"""Expire the JWT-era refresh cookie, which lived at a path we no longer use.

	Cookie deletion is path-scoped, so the new cookie's own deletion cannot reach
	it. Drop this once the cutover has aged past the old cookie's Max-Age.
	"""
	response.delete_cookie(
		settings.LEGACY_REFRESH_COOKIE_NAME,
		path=settings.LEGACY_REFRESH_COOKIE_PATH,
		samesite=_session_cookie_samesite(),
	)


def _bearer_session_token(request: Request) -> str:
	"""The token from ``Authorization: Session <token>``, or "" if there is none.

	Tolerant by design: both callers are anonymous endpoints doing a manual
	lookup, and a malformed header there means "no credential presented", not an
	error worth failing the request over.
	"""
	header = get_authorization_header(request).split()
	if len(header) != 2 or header[0].lower() != AUTH_SCHEME.lower().encode():
		return ""
	try:
		return header[1].decode()
	except UnicodeError:
		return ""


def _presented_session_token(request: Request) -> str:
	"""Whatever session credential rode along with this request, header first."""
	return _bearer_session_token(request) or request.COOKIES.get(settings.SESSION_TOKEN_COOKIE_NAME, "")


def _device_label(raw: Any) -> str:
	if not isinstance(raw, str):
		return ""
	return raw.strip()[:120]


def _user_agent(request: Request) -> str:
	return str(request.META.get("HTTP_USER_AGENT", ""))[:256]


def _ensure_dev_user(username: str, password: str) -> None:
	"""Create (or reanimate) the dev bootstrap account on first dev login.

	Guarded by DEV_BOOTSTRAP_LOGIN_ENABLED, which defaults to DEBUG. The
	credentials must match exactly, so this never turns a failed login for a real
	account into an account creation.
	"""
	if not settings.DEV_BOOTSTRAP_LOGIN_ENABLED:
		return
	if username != settings.DEV_BOOTSTRAP_USERNAME or password != settings.DEV_BOOTSTRAP_PASSWORD:
		return

	existing_user = User._base_manager.filter(username=username).first()
	if existing_user is not None:
		if existing_user.date_deleted is not None or not existing_user.is_active:
			existing_user.date_deleted = None
			existing_user.is_active = True
			existing_user.save(update_fields=["date_deleted", "is_active", "date_modified"])
		return

	User.objects.create_user(
		email=settings.DEV_BOOTSTRAP_EMAIL,
		username=settings.DEV_BOOTSTRAP_USERNAME,
		password=settings.DEV_BOOTSTRAP_PASSWORD,
		name=settings.DEV_BOOTSTRAP_NAME,
	)


# ── login / logout ───────────────────────────────────────────


class LoginView(AuthThrottleMixin, APIView):
	"""Exchange credentials for exactly one session on exactly one transport.

	``authentication_classes = []`` because DRF authenticates before permissions
	and rethrows failures: a stale cookie riding along must not 401 the request
	before the view ever runs. ``AllowAny`` because the project default is
	``IsAuthenticated``, which would reject the (necessarily anonymous) caller.
	"""

	authentication_classes: list[type[Any]] = []
	permission_classes = [AllowAny]
	parser_classes = [JSONParser]
	throttle_scope = "login"

	@extend_schema(
		request=LoginRequestSerializer,
		responses={
			status.HTTP_200_OK: LoginResponseSerializer,
			status.HTTP_400_BAD_REQUEST: OpenApiResponse(
				description="Body was not JSON, or transport/credentials fields were missing or invalid."
			),
			status.HTTP_401_UNAUTHORIZED: OpenApiResponse(
				description="Invalid credentials, or the account changed while the login was in flight."
			),
		},
	)
	def post(self, request: Request) -> Response:
		_require_json_request(request)
		serializer = LoginRequestSerializer(data=request.data)
		serializer.is_valid(raise_exception=True)
		username = serializer.validated_data["username"]
		password = serializer.validated_data["password"]
		transport = serializer.validated_data["transport"]
		device_label = _device_label(serializer.validated_data.get("device_label"))

		_ensure_dev_user(username, password)
		user = authenticate(request=request._request, username=username, password=password)
		if not isinstance(user, User):
			# Explicit response rather than AuthenticationFailed: with no
			# authenticators on this view DRF would coerce that exception to 403,
			# and a rejected password is not a forbidden request.
			return _no_store(Response({"detail": "Invalid credentials."}, status=status.HTTP_401_UNAUTHORIZED))

		try:
			issued = create_session(
				user=user,
				transport=transport,
				device_label=device_label,
				ip=client_ip(request) or None,
				user_agent=_user_agent(request),
				password_hash_at_login=user.password,
				# A live session presented alongside a login is being replaced on
				# this device, so it dies in the same transaction rather than
				# lingering as an orphaned live row nobody can reach.
				replaces_token=_presented_session_token(request) or None,
			)
		except SessionLoginAbortedError:
			return _no_store(
				Response(
					{"detail": "The account changed while signing in. Try again."},
					status=status.HTTP_401_UNAUTHORIZED,
				)
			)

		if transport == DeviceSession.Transport.COOKIE:
			body = {"transport": transport, "public_id": str(issued.session.public_id), "token": None}
			response = _no_store(Response(body, status=status.HTTP_200_OK))
			_set_session_cookie(response, issued.token)
			_clear_legacy_refresh_cookie(response)
			# Rotate on privilege change, as Django's own login() does, and so
			# that CsrfViewMiddleware emits a fresh readable csrftoken cookie for
			# the SPA to echo back on writes. Must be the underlying HttpRequest:
			# the flag lives in META, which is what the middleware reads later.
			rotate_token(request._request)
			return response

		body = {"transport": transport, "public_id": str(issued.session.public_id), "token": issued.token}
		response = _no_store(Response(body, status=status.HTTP_200_OK))
		_clear_legacy_refresh_cookie(response)
		return response


class LogoutView(AuthThrottleMixin, APIView):
	"""End the presented session, idempotently, and clear the cookie regardless.

	Anonymous by construction (see LoginView), and tolerant: an expired, revoked
	or unknown credential is not an error — the caller wants to be signed out and
	already is.
	"""

	authentication_classes: list[type[Any]] = []
	permission_classes = [AllowAny]
	parser_classes = [JSONParser]
	throttle_scope = "logout"

	@extend_schema(
		request=None,
		responses={
			status.HTTP_200_OK: StatusResponseSerializer,
			status.HTTP_400_BAD_REQUEST: OpenApiResponse(description="Body was not JSON."),
			status.HTTP_403_FORBIDDEN: OpenApiResponse(
				description="A live cookie session was presented without a valid CSRF token."
			),
		},
	)
	def post(self, request: Request) -> Response:
		# Before anything that could emit Set-Cookie. A cross-site top-level form
		# POST omits the SameSite=Strict cookie, but browsers still *apply*
		# Set-Cookie from such a response — so an ungated logout would let any
		# origin delete a session it never held. The cookie deletions below
		# cannot be conditioned on presentation (the legacy cookie is invisible
		# to us at its old path), which makes this gate the only defence.
		_require_json_request(request)

		bearer_token = _bearer_session_token(request)
		if bearer_token:
			revoke_session_for_token(bearer_token, reason=DeviceSession.RevokeReason.LOGOUT)

		cookie_token = request.COOKIES.get(settings.SESSION_TOKEN_COOKIE_NAME, "")
		if cookie_token:
			live = session_for_token(cookie_token, transport=DeviceSession.Transport.COOKIE)
			if live is not None:
				# CSRF is conditional on liveness: revoking a live session is a
				# protected mutation, clearing a dead cookie is not. Enforced
				# here because this view has no authenticator to do it.
				SessionAuthentication().enforce_csrf(request)
				revoke_session_for_token(cookie_token, reason=DeviceSession.RevokeReason.LOGOUT)

		response = _no_store(Response({"status": "ok"}, status=status.HTTP_200_OK))
		_clear_session_cookie(response)
		_clear_legacy_refresh_cookie(response)
		return response


def _no_store(response: Response) -> Response:
	response["Cache-Control"] = "no-store"
	return response


# ── device sessions ──────────────────────────────────────────


@extend_schema_view(
	list=extend_schema(
		summary="List the caller's live sessions",
		description=(
			"Every signed-in device that can still authenticate for the requesting user, most "
			"recently used first. Revoked sessions, sessions idle past the idle lifetime, and "
			"sessions past the absolute lifetime are omitted. Strictly owner-scoped: a user never "
			"sees another user's sessions. Bounded by the per-user session cap, so it is never paginated."
		),
		responses={
			status.HTTP_200_OK: DeviceSessionSerializer(many=True),
			status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication credentials were not provided."),
		},
	)
)
class DeviceSessionViewSet(ListModelMixin, _DeviceSessionGenericViewSet):
	"""Inspect and revoke the requesting user's own device sessions."""

	permission_classes = [IsAuthenticated]
	serializer_class = DeviceSessionSerializer
	# Metadata only — get_queryset() below is what actually runs. Declared so
	# drf-spectacular can derive the model (and therefore the {public_id} path
	# parameter's type) without calling get_queryset() with an AnonymousUser.
	queryset = DeviceSession.objects.none()
	lookup_field = "public_id"
	lookup_url_kwarg = "public_id"

	def get_queryset(self) -> QuerySet[DeviceSession]:
		user = self.request.user
		if not isinstance(user, User):
			return DeviceSession.objects.none()
		return live_sessions_for_user(user)

	@extend_schema(
		summary="Revoke one session",
		description=(
			"Revokes a single session by its public_id, signing that device out on its next request. "
			"Scoped to the caller's own live sessions, so another user's public_id resolves to 404 "
			"rather than revealing that it exists. Revoking the caller's own session is allowed — "
			"that is how you sign out a device you are holding."
		),
		request=None,
		responses={
			status.HTTP_200_OK: SessionRevokeResponseSerializer,
			status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication credentials were not provided."),
			status.HTTP_404_NOT_FOUND: OpenApiResponse(description="No such live session for this user."),
		},
	)
	def destroy(self, request: Request, public_id: str | None = None) -> Response:
		session = self.get_object()
		session.revoke(DeviceSession.RevokeReason.REVOKED_BY_USER)
		return Response({"status": "ok", "revoked": 1})

	@extend_schema(
		summary="Revoke every other session",
		description=(
			"Signs the caller out on every device except the one making the request, matching what "
			"changing the password does. Returns how many sessions were revoked; already-revoked "
			"sessions are left untouched so their original reason and timestamp survive."
		),
		request=None,
		responses={
			status.HTTP_200_OK: SessionRevokeResponseSerializer,
			status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication credentials were not provided."),
		},
	)
	@action(detail=False, methods=["post"], url_path="revoke_all")
	def revoke_all(self, request: Request) -> Response:
		user = request.user
		assert isinstance(user, User), "revoking sessions requires an application User"
		caller = request.auth if isinstance(request.auth, DeviceSession) else None
		revoked = revoke_all_sessions_for_user(
			user,
			reason=DeviceSession.RevokeReason.REVOKED_BY_USER,
			except_session=caller,
		)
		return Response({"status": "ok", "revoked": revoked})


# ── users ────────────────────────────────────────────────────


class UserViewSet(_UserModelViewSet):
	permission_classes = [IsAuthenticated, (ReadOnly | IsRequestingThemselves | IsAdminUser)]
	queryset = User.objects.all()

	def get_throttles(self) -> list[BaseThrottle]:
		"""Apply stricter 'register' throttle on account creation."""
		if self.action == "create" and not settings.TESTING:
			self.throttle_scope = "register"
			return [*super().get_throttles(), ScopedRateThrottle()]
		return super().get_throttles()

	def get_serializer_class(self) -> type[BaseSerializer[User]]:
		requester_pk = self.request.user.pk if not self.request.user.is_anonymous else None
		wanted_pk = self.kwargs.get("pk", None)

		# wanted_pk is a bare name in the case pattern below, which makes it a
		# *capture* pattern rather than a comparison against the local of the
		# same name - it rebinds to whatever the match subject holds there
		# (requester_pk), shadowing the assignment above. That previously made
		# the guard test requester_pk instead of wanted_pk, so every
		# authenticated GET - including the list endpoint - matched and got the
		# full serializer. Comparing under a different name, and as strings
		# since kwargs["pk"] is a string, keeps this a real equality check.
		match (self.request.method, requester_pk):
			case ("POST" | "PUT" | "PATCH", _):
				return UserCreationSerializer
			case ("GET", requester) if requester is not None and wanted_pk is not None and str(requester) == wanted_pk:
				return UserFullReadSerializer
			case _:
				return UserMinimalReadSerializer

	def get_permissions(self) -> Sequence[Any]:
		# Account creation, ie. registration, needs to work for visitors without an
		# account. This is keyed on the action rather than the HTTP method because
		# keying on the method also stripped IsAuthenticated off every POST @action
		# on this viewset — change_password and get_my_info — which then reached
		# their `assert isinstance(user, User)` with an AnonymousUser and returned
		# 500 to unauthenticated callers.
		if self.action == "create":
			return []

		return super().get_permissions()

	@action(detail=False, methods=["get", "post"], permission_classes=[IsAuthenticated])
	def get_my_info(self, request: Request) -> Response:
		user = request.user
		assert isinstance(user, User)
		return Response(status=status.HTTP_200_OK, data=UserFullReadSerializer(user).data)

	@action(detail=False, methods=["post"], permission_classes=[IsAuthenticated])
	def change_password(self, request: Request) -> Response:
		"""Change the authenticated user's password.

		Requires current_password for verification.  Returns 400 on wrong
		current password or validation failure.
		"""
		user = request.user
		assert isinstance(user, User)

		# DRF types request.data as dict | list; this endpoint requires a JSON
		# object body, so narrow before reading individual fields.
		body = request.data
		assert isinstance(body, dict)

		current_password = body.get("current_password")
		new_password = body.get("new_password")

		if not current_password or not new_password:
			return Response(
				{"error": "Both current_password and new_password are required."},
				status=status.HTTP_400_BAD_REQUEST,
			)

		if not user.check_password(current_password):
			return Response(
				{"error": "Current password is incorrect."},
				status=status.HTTP_400_BAD_REQUEST,
			)

		try:
			from django.contrib.auth.password_validation import validate_password

			validate_password(new_password, user)
		except DjangoValidationError as exc:
			return Response(
				{"error": str(exc)},
				status=status.HTTP_400_BAD_REQUEST,
			)

		# One transaction: a password that no longer matches the sessions that
		# can use it is exactly the split-brain this feature exists to prevent.
		with transaction.atomic():
			user.set_password(new_password)
			user.save(update_fields=["password", "date_modified"])
			# Evict every other session, but keep the one that just proved it
			# knows the current password - matching the account screen's "you
			# will stay logged in" promise.
			revoke_all_sessions_for_user(
				user,
				reason=DeviceSession.RevokeReason.PASSWORD_CHANGE,
				except_session=request.auth if isinstance(request.auth, DeviceSession) else None,
			)

		return Response({"status": "ok"})


# ── password reset ───────────────────────────────────────────


class PasswordResetRequestView(APIView):
	"""Send a password reset code to the given email address.

	Always returns 200 regardless of whether the email exists,
	to prevent user enumeration.  If the user exists, a 6-digit
	code is generated, stored, and emailed.
	"""

	permission_classes = [AllowAny]
	parser_classes = [JSONParser]
	throttle_scope = "password_reset"

	def get_throttles(self) -> list[BaseThrottle]:
		if settings.TESTING:
			return []
		return [UserRateThrottle(), ScopedRateThrottle()]

	@extend_schema(
		request=PasswordResetRequestSerializer,
		responses={status.HTTP_200_OK: StatusResponseSerializer},
	)
	def post(self, request: Request) -> Response:
		# Same cross-site form gate as login/logout: without it, any webpage
		# could POST form-encoded resets from the victim's browser — minting
		# codes (invalidating the victim's own), flooding their inbox, and
		# spending the per-IP throttle budget from the victim's IP.
		_require_json_request(request)
		from accounts.models.password_reset import PasswordResetCode

		serializer = PasswordResetRequestSerializer(data=request.data)
		if not serializer.is_valid():
			# Return 200 to prevent enumeration via validation errors
			return Response({"status": "ok"})

		email = Email(serializer.validated_data["email"])
		if not _email_budget_allows("request", email, *_PASSWORD_RESET_REQUEST_BUDGET):
			# Budget exhausted: answer identically and silently. This per-email
			# cap is what makes the mint-new-code-to-reset-the-lockout loop
			# useless: a fresh code cannot buy more guesses than the budget.
			return Response({"status": "ok"})

		user = User._base_manager.filter(email__iexact=email, is_active=True).first()

		if user is not None:
			import secrets

			code = str(secrets.randbelow(1_000_000)).zfill(6)

			PasswordResetCode.issue_for_user(user=user, code=code)

			try:
				_send_reset_email(Email(user.email), code)
			except Exception:
				# The silent 200 is the anti-enumeration contract: a dispatch
				# failure must not surface as a 500 that only existing accounts
				# can trigger.
				logger.exception("Password reset email dispatch failed for %s", user.email)

		return Response({"status": "ok"})


class PasswordResetConfirmView(APIView):
	"""Validate a reset code and set a new password."""

	permission_classes = [AllowAny]
	parser_classes = [JSONParser]
	throttle_scope = "password_reset_confirm"

	def get_throttles(self) -> list[BaseThrottle]:
		if settings.TESTING:
			return []
		return [UserRateThrottle(), ScopedRateThrottle()]

	@extend_schema(
		request=PasswordResetConfirmSerializer,
		responses={status.HTTP_200_OK: StatusResponseSerializer},
	)
	def post(self, request: Request) -> Response:
		# JSON-only, like the request endpoint: form-encoded cross-site POSTs
		# must not be able to burn guesses against the victim's code from the
		# victim's browser.
		_require_json_request(request)
		from accounts.models.password_reset import PasswordResetCode

		serializer = PasswordResetConfirmSerializer(data=request.data)
		if not serializer.is_valid():
			return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

		email = Email(serializer.validated_data["email"])
		code = serializer.validated_data["code"]
		new_password = serializer.validated_data["new_password"]

		if not _email_budget_allows("confirm", email, *_PASSWORD_RESET_CONFIRM_BUDGET):
			# Budget exhausted: the same error as a wrong code, so the endpoint
			# never advertises that guesses are being counted.
			return Response(
				{"error": "Invalid or expired reset code."},
				status=status.HTTP_400_BAD_REQUEST,
			)

		user = User._base_manager.filter(email__iexact=email, is_active=True).first()
		if user is None:
			return Response(
				{"error": "Invalid or expired reset code."},
				status=status.HTTP_400_BAD_REQUEST,
			)

		reset_code = PasswordResetCode.objects.filter(user=user).order_by("-created_at").first()
		if reset_code is None or reset_code.is_expired or reset_code.is_locked:
			return Response(
				{"error": "Invalid or expired reset code."},
				status=status.HTTP_400_BAD_REQUEST,
			)
		if not reset_code.check_code(code):
			reset_code.record_failure()
			return Response(
				{"error": "Invalid or expired reset code."},
				status=status.HTTP_400_BAD_REQUEST,
			)

		# Validate password against this specific user
		try:
			from django.contrib.auth.password_validation import (
				validate_password,
			)

			validate_password(new_password, user)
		except DjangoValidationError as exc:
			return Response(
				{"error": str(exc)},
				status=status.HTTP_400_BAD_REQUEST,
			)

		# One transaction: the new password, the eviction of every session, and
		# the consumption of the reset code land together or not at all. Reset
		# spares nothing - it exists for the case where the credential may be in
		# the wrong hands, and the caller has no session to spare anyway.
		with transaction.atomic():
			user.set_password(new_password)
			user.save(update_fields=["password", "date_modified"])
			revoke_all_sessions_for_user(user, reason=DeviceSession.RevokeReason.PASSWORD_CHANGE)

			# Clean up used code
			PasswordResetCode.objects.filter(user=user).delete()

		return Response({"status": "ok"})
