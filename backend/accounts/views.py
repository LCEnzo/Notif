import logging
from collections.abc import Sequence
from typing import TYPE_CHECKING, Any, Literal, cast

from django.conf import settings
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.db.models.query import QuerySet
from drf_spectacular.utils import OpenApiParameter, OpenApiResponse, extend_schema, extend_schema_view
from rest_framework import status
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
from rest_framework_simplejwt.serializers import TokenObtainSerializer
from rest_framework_simplejwt.views import TokenObtainPairView, TokenVerifyView

from accounts.models import RefreshSessionFamily, User
from accounts.refresh_sessions import (
	REFRESH_REQUEST_HEADER,
	REFRESH_REQUEST_HEADER_VALUE,
	RefreshSessionError,
	RefreshTokenReuseError,
	active_refresh_families_for_user,
	family_id_from_access_token,
	issue_tokens_for_login,
	refresh_lifetime_seconds,
	revoke_all_refresh_families_for_user,
	revoke_refresh_family_for_token,
	rotate_refresh_token,
)
from accounts.serializers import (
	PasswordResetConfirmSerializer,
	PasswordResetRequestSerializer,
	RefreshSessionRevokeResponseSerializer,
	RefreshSessionSerializer,
	TokenAccessResponseSerializer,
	TokenLoginRequestSerializer,
	TokenLogoutResponseSerializer,
	TokenRefreshRequestSerializer,
	UserCreationSerializer,
	UserFullReadSerializer,
	UserMinimalReadSerializer,
)
from commons.permissions import IsRequestingThemselves, ReadOnly

if TYPE_CHECKING:
	_UserModelViewSet = ModelViewSet[User]
	_RefreshSessionGenericViewSet = GenericViewSet[RefreshSessionFamily]
else:
	_UserModelViewSet = ModelViewSet
	_RefreshSessionGenericViewSet = GenericViewSet


class DevBootstrapTokenObtainPairSerializer(TokenObtainSerializer):
	def validate(self, attrs: dict[str, Any]) -> dict[str, Any]:
		self._ensure_dev_user(attrs)
		super().validate(attrs)
		assert isinstance(self.user, User), "token login requires an application User"
		request = self.context["request"]
		assert isinstance(request, Request)
		remember_me = _wants_remember_me(request.data.get("remember_me"))
		tokens = issue_tokens_for_login(user=self.user, remember_me=remember_me, request=request)
		data = {"access": tokens.access}
		if tokens.refresh is not None:
			data["refresh"] = tokens.refresh
		return data

	def _ensure_dev_user(self, attrs: dict[str, Any]) -> None:
		if not settings.DEV_BOOTSTRAP_LOGIN_ENABLED:
			return

		username = attrs.get(self.username_field)
		password = attrs.get("password")
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


logger = logging.getLogger(__name__)
RefreshCookieSameSite = Literal["Lax", "Strict", "None", False]


class TokenThrottleMixin:
	"""Disables throttling in tests; applies UserRateThrottle + ScopedRateThrottle otherwise.

	Subclasses must set throttle_scope so ScopedRateThrottle picks up the right rate.
	"""

	throttle_scope: str

	def get_throttles(self) -> list[BaseThrottle]:
		if settings.TESTING:
			return []
		return [UserRateThrottle(), ScopedRateThrottle()]


def _refresh_cookie_max_age() -> int:
	return refresh_lifetime_seconds()


def _refresh_cookie_samesite() -> RefreshCookieSameSite:
	return cast(RefreshCookieSameSite, settings.JWT_REFRESH_COOKIE_SAMESITE)


def _set_refresh_cookie(response: Response, refresh_token: str) -> None:
	response.set_cookie(
		settings.JWT_REFRESH_COOKIE_NAME,
		refresh_token,
		max_age=_refresh_cookie_max_age(),
		path=settings.JWT_REFRESH_COOKIE_PATH,
		secure=settings.JWT_REFRESH_COOKIE_SECURE,
		httponly=True,
		samesite=_refresh_cookie_samesite(),
	)
	response["Cache-Control"] = "no-store"


def _clear_refresh_cookie(response: Response) -> None:
	response.delete_cookie(
		settings.JWT_REFRESH_COOKIE_NAME,
		path=settings.JWT_REFRESH_COOKIE_PATH,
		samesite=_refresh_cookie_samesite(),
	)
	response["Cache-Control"] = "no-store"


def _revoke_existing_refresh_cookie(request: Request) -> None:
	raw_refresh_token = request.COOKIES.get(settings.JWT_REFRESH_COOKIE_NAME, "")
	if raw_refresh_token:
		revoke_refresh_family_for_token(
			raw_refresh_token,
			reason=RefreshSessionFamily.RevokeReason.LOGIN_REPLACED,
		)


def _wants_remember_me(raw: Any) -> bool:
	if raw is None:
		return True
	if isinstance(raw, bool):
		return raw
	if isinstance(raw, str):
		return raw.strip().lower() not in {"0", "false", "no", "off"}
	return bool(raw)


def _require_refresh_request_header(request: Request) -> None:
	if request.META.get(REFRESH_REQUEST_HEADER) != REFRESH_REQUEST_HEADER_VALUE:
		raise ValidationError({"X-Refresh-Request": "Refresh requests must include X-Refresh-Request: 1."})


def _is_json_content_type(request: Request) -> bool:
	media_type = (request.content_type or "").split(";", 1)[0].strip().lower()
	return media_type == "application/json"


def _require_non_simple_request(request: Request) -> None:
	"""Reject anything a cross-site HTML form could have produced.

	DRF marks its views ``csrf_exempt``, SimpleJWT's token views clear
	``authentication_classes``, and DRF's default ``FormParser`` is enabled — so
	without this gate a top-level form POST from any site is a CORS *simple
	request*: no preflight, no CSRF token, and the browser happily stores the
	``Set-Cookie: notif_refresh`` that comes back. On ``/token/`` that plants the
	attacker's session in the victim's browser (the victim's app then silently
	authenticates into the attacker's account); on ``/token/logout/`` it drops an
	arbitrary user's session.

	An HTML form can only send ``application/x-www-form-urlencoded``,
	``multipart/form-data`` or ``text/plain``, and it cannot set request headers.
	Either signal therefore proves the request was not one: a custom header, or a
	JSON content type.

	``X-Refresh-Request: 1`` is the preferred signal, but the Flutter client only
	sends it on ``/token/refresh/`` — login and logout send just
	``Content-Type: application/json``. Both are accepted here so the shipped client
	keeps working; ``parser_classes = [JSONParser]`` on the token views makes the
	content-type branch structural rather than advisory (a form-encoded body cannot
	be parsed at all, even if the header is present). Once the client sends the
	header on login/logout too, drop the content-type branch and call
	``_require_refresh_request_header`` everywhere.
	"""
	if request.META.get(REFRESH_REQUEST_HEADER) == REFRESH_REQUEST_HEADER_VALUE:
		return
	if _is_json_content_type(request):
		return
	raise ValidationError(
		{
			"X-Refresh-Request": (
				"Send X-Refresh-Request: 1 or a JSON request body. Form-encoded requests are "
				"rejected because a cross-site form could forge them."
			)
		}
	)


def _refresh_request_header_parameter(*, required: bool) -> OpenApiParameter:
	return OpenApiParameter(
		name="X-Refresh-Request",
		type=str,
		location=OpenApiParameter.HEADER,
		required=required,
		description=(
			"Set to 1. Proves the request did not come from a cross-site HTML form. "
			+ (
				"Required."
				if required
				else "Optional only because a JSON request body proves the same thing; one of the two is required."
			)
		),
	)


class DevBootstrapTokenObtainPairView(TokenThrottleMixin, TokenObtainPairView):
	serializer_class = DevBootstrapTokenObtainPairSerializer
	# JSON only. A cross-site HTML form cannot produce this content type, which is
	# what stops an attacker from planting their own notif_refresh cookie in a
	# victim's browser via a top-level form POST to this endpoint.
	parser_classes = [JSONParser]
	throttle_scope = "login"

	@extend_schema(
		parameters=[_refresh_request_header_parameter(required=False)],
		request=TokenLoginRequestSerializer,
		responses={
			status.HTTP_200_OK: TokenAccessResponseSerializer,
			status.HTTP_400_BAD_REQUEST: OpenApiResponse(
				description="Request was not proven non-cross-site (see X-Refresh-Request), or the body was invalid."
			),
			status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Invalid credentials."),
		},
	)
	def post(self, request: Request, *args: Any, **kwargs: Any) -> Response:
		_require_non_simple_request(request)
		response = super().post(request, *args, **kwargs)
		if not isinstance(response.data, dict):
			return response

		_revoke_existing_refresh_cookie(request)
		remember_me = _wants_remember_me(request.data.get("remember_me"))
		refresh_token = response.data.pop("refresh", None)
		if not remember_me:
			_clear_refresh_cookie(response)
			return response

		if isinstance(refresh_token, str) and refresh_token:
			_set_refresh_cookie(response, refresh_token)
		return response


class ThrottledTokenRefreshView(TokenThrottleMixin, APIView):
	permission_classes = [AllowAny]
	parser_classes = [JSONParser]
	throttle_scope = "token_refresh"

	def get_throttles(self) -> list[BaseThrottle]:
		"""Scoped throttle only — see the token_refresh comment in settings.py.

		The endpoint authenticates by cookie, so DRF sees an anonymous caller and
		``UserRateThrottle`` also keys on IP at the "user" rate (500/hour ≈ 8/min).
		Stacking it under a per-minute scope just made the coarser limit bind first
		and turned a NAT full of users into forced logouts.
		"""
		if settings.TESTING:
			return []
		return [ScopedRateThrottle()]

	@extend_schema(
		parameters=[_refresh_request_header_parameter(required=True)],
		request=TokenRefreshRequestSerializer,
		responses={
			status.HTTP_200_OK: TokenAccessResponseSerializer,
			status.HTTP_400_BAD_REQUEST: OpenApiResponse(description="Missing the X-Refresh-Request header."),
			status.HTTP_401_UNAUTHORIZED: OpenApiResponse(
				description="Refresh cookie missing, expired, revoked, or replayed outside the rotation grace window."
			),
		},
	)
	def post(self, request: Request, *args: Any, **kwargs: Any) -> Response:
		_require_refresh_request_header(request)
		try:
			tokens = rotate_refresh_token(request.COOKIES.get(settings.JWT_REFRESH_COOKIE_NAME, ""))
		except RefreshTokenReuseError as exc:
			response = Response({"detail": str(exc)}, status=status.HTTP_401_UNAUTHORIZED)
			_clear_refresh_cookie(response)
			return response
		except RefreshSessionError as exc:
			response = Response({"detail": str(exc)}, status=status.HTTP_401_UNAUTHORIZED)
			_clear_refresh_cookie(response)
			return response

		response = Response({"access": tokens.access}, status=status.HTTP_200_OK)
		_set_refresh_cookie(response, tokens.refresh)
		return response


class ThrottledTokenLogoutView(TokenThrottleMixin, APIView):
	permission_classes = [AllowAny]
	parser_classes = [JSONParser]
	throttle_scope = "token_logout"

	@extend_schema(
		parameters=[_refresh_request_header_parameter(required=False)],
		request=TokenRefreshRequestSerializer,
		responses={
			status.HTTP_200_OK: TokenLogoutResponseSerializer,
			status.HTTP_400_BAD_REQUEST: OpenApiResponse(
				description="Request was not proven non-cross-site (see X-Refresh-Request)."
			),
		},
	)
	def post(self, request: Request) -> Response:
		_require_non_simple_request(request)
		raw_refresh_token = request.COOKIES.get(settings.JWT_REFRESH_COOKIE_NAME, "")
		response = Response({"status": "ok"}, status=status.HTTP_200_OK)
		response["Cache-Control"] = "no-store"
		if not raw_refresh_token:
			# Nothing was presented, so there is nothing to revoke and nothing to
			# clear. Emitting a Set-Cookie here would let any origin that can reach
			# this endpoint drop a session it never held.
			return response

		revoke_refresh_family_for_token(
			raw_refresh_token,
			reason=RefreshSessionFamily.RevokeReason.LOGOUT,
		)
		_clear_refresh_cookie(response)
		return response


class ThrottledTokenVerifyView(TokenThrottleMixin, TokenVerifyView):
	parser_classes = [JSONParser]
	throttle_scope = "token_verify"


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

		match (self.request.method, requester_pk):
			case ("POST" | "PUT" | "PATCH", _):
				return UserCreationSerializer
			case ("GET", wanted_pk) if wanted_pk is not None:
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

		current_password = request.data.get("current_password")
		new_password = request.data.get("new_password")

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
			# will stay logged in" promise. The current session is identified
			# by the family claim its access token inherited from rotation.
			revoke_all_refresh_families_for_user(
				user,
				reason=RefreshSessionFamily.RevokeReason.PASSWORD_CHANGE,
				except_family=family_id_from_access_token(request.auth),
			)

		return Response({"status": "ok"})


# ── refresh sessions ─────────────────────────────────────────


@extend_schema_view(
	list=extend_schema(
		summary="List the caller's active sessions",
		description=(
			"Every refresh session (signed-in device) that can still mint access tokens for the "
			"requesting user, most recently used first. Sessions that are revoked, stale beyond the "
			"refresh token lifetime, or past the absolute session lifetime are omitted. Strictly "
			"owner-scoped: a user never sees another user's sessions."
		),
		responses={
			status.HTTP_200_OK: RefreshSessionSerializer(many=True),
			status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication credentials were not provided."),
		},
	)
)
class RefreshSessionViewSet(ListModelMixin, _RefreshSessionGenericViewSet):
	"""Inspect and revoke the requesting user's own refresh sessions."""

	permission_classes = [IsAuthenticated]
	serializer_class = RefreshSessionSerializer
	# Metadata only — get_queryset() below is what actually runs. Declared so
	# drf-spectacular can derive the model (and therefore the {family_id} path
	# parameter's type) without calling get_queryset() with an AnonymousUser.
	queryset = RefreshSessionFamily.objects.none()
	lookup_field = "family_id"
	lookup_url_kwarg = "family_id"

	def get_queryset(self) -> QuerySet[RefreshSessionFamily]:
		user = self.request.user
		if not isinstance(user, User):
			return RefreshSessionFamily.objects.none()
		return active_refresh_families_for_user(user)

	@extend_schema(
		summary="Revoke one session",
		description=(
			"Revokes a single session by its family_id, signing that device out at its next refresh. "
			"Scoped to the caller's own sessions, so another user's family_id resolves to 404 rather "
			"than revealing that it exists."
		),
		request=None,
		responses={
			status.HTTP_200_OK: RefreshSessionRevokeResponseSerializer,
			status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication credentials were not provided."),
			status.HTTP_404_NOT_FOUND: OpenApiResponse(description="No such active session for this user."),
		},
	)
	@action(detail=True, methods=["post"])
	def revoke(self, request: Request, family_id: str | None = None) -> Response:
		family = self.get_object()
		family.revoke(RefreshSessionFamily.RevokeReason.REVOKED_BY_USER)
		return Response({"status": "ok", "revoked": 1})

	@extend_schema(
		summary="Revoke every session",
		description=(
			"Signs the caller out everywhere, including the device making the request. Returns how "
			"many sessions were revoked; already-revoked sessions are left untouched so their "
			"original reason and timestamp survive."
		),
		request=None,
		responses={
			status.HTTP_200_OK: RefreshSessionRevokeResponseSerializer,
			status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication credentials were not provided."),
		},
	)
	@action(detail=False, methods=["post"], url_path="revoke-all")
	def revoke_all(self, request: Request) -> Response:
		user = request.user
		assert isinstance(user, User), "revoking sessions requires an application User"
		revoked = revoke_all_refresh_families_for_user(
			user,
			reason=RefreshSessionFamily.RevokeReason.REVOKED_BY_USER,
		)
		return Response({"status": "ok", "revoked": revoked})


# ── password reset ───────────────────────────────────────────


class PasswordResetRequestView(APIView):
	"""Send a password reset code to the given email address.

	Always returns 200 regardless of whether the email exists,
	to prevent user enumeration.  If the user exists, a 6-digit
	code is generated, stored, and emailed.
	"""

	permission_classes = [AllowAny]
	throttle_scope = "password_reset"

	def get_throttles(self) -> list[BaseThrottle]:
		if settings.TESTING:
			return []
		return [UserRateThrottle(), ScopedRateThrottle()]

	@extend_schema(
		request=PasswordResetRequestSerializer,
		responses={status.HTTP_200_OK: TokenLogoutResponseSerializer},
	)
	def post(self, request: Request) -> Response:
		from accounts.models.password_reset import PasswordResetCode
		from commons.email import send_password_reset_email

		serializer = PasswordResetRequestSerializer(data=request.data)
		if not serializer.is_valid():
			# Return 200 to prevent enumeration via validation errors
			return Response({"status": "ok"})

		email = serializer.validated_data["email"]
		user = User._base_manager.filter(email__iexact=email, is_active=True).first()

		if user is not None:
			import secrets

			code = str(secrets.randbelow(1_000_000)).zfill(6)

			PasswordResetCode.issue_for_user(user=user, code=code)

			try:
				send_password_reset_email(user.email, code)
			except Exception:
				logger.exception("Failed to send reset email to %s", email)
				# Always return 200 - even a send failure during an email
				# outage must not become an email-enumeration oracle.

		return Response({"status": "ok"})


class PasswordResetConfirmView(APIView):
	"""Validate a reset code and set a new password."""

	permission_classes = [AllowAny]
	throttle_scope = "password_reset_confirm"

	def get_throttles(self) -> list[BaseThrottle]:
		if settings.TESTING:
			return []
		return [UserRateThrottle(), ScopedRateThrottle()]

	@extend_schema(
		request=PasswordResetConfirmSerializer,
		responses={status.HTTP_200_OK: TokenLogoutResponseSerializer},
	)
	def post(self, request: Request) -> Response:
		from accounts.models.password_reset import PasswordResetCode

		serializer = PasswordResetConfirmSerializer(data=request.data)
		if not serializer.is_valid():
			return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

		email = serializer.validated_data["email"]
		code = serializer.validated_data["code"]
		new_password = serializer.validated_data["new_password"]

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
		# the consumption of the reset code land together or not at all.
		with transaction.atomic():
			user.set_password(new_password)
			user.save(update_fields=["password", "date_modified"])
			revoke_all_refresh_families_for_user(user, reason=RefreshSessionFamily.RevokeReason.PASSWORD_CHANGE)

			# Clean up used code
			PasswordResetCode.objects.filter(user=user).delete()

		return Response({"status": "ok"})
