import logging
from collections.abc import Sequence
from typing import TYPE_CHECKING, Any, Literal, cast

from django.conf import settings
from django.core.exceptions import ValidationError as DjangoValidationError
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny, IsAdminUser, IsAuthenticated
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.serializers import BaseSerializer
from rest_framework.throttling import BaseThrottle, ScopedRateThrottle, UserRateThrottle
from rest_framework.views import APIView
from rest_framework.viewsets import ModelViewSet
from rest_framework_simplejwt.serializers import TokenObtainSerializer
from rest_framework_simplejwt.views import TokenObtainPairView, TokenVerifyView

from accounts.models import RefreshSessionFamily, User
from accounts.refresh_sessions import (
	REFRESH_REQUEST_HEADER,
	REFRESH_REQUEST_HEADER_VALUE,
	RefreshSessionError,
	RefreshTokenReuseError,
	issue_tokens_for_login,
	refresh_lifetime_seconds,
	revoke_refresh_family_for_token,
	rotate_refresh_token,
)
from accounts.serializers import (
	PasswordResetConfirmSerializer,
	PasswordResetRequestSerializer,
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
else:
	_UserModelViewSet = ModelViewSet


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


class DevBootstrapTokenObtainPairView(TokenThrottleMixin, TokenObtainPairView):
	serializer_class = DevBootstrapTokenObtainPairSerializer
	throttle_scope = "login"

	@extend_schema(
		request=TokenLoginRequestSerializer,
		responses={status.HTTP_200_OK: TokenAccessResponseSerializer},
	)
	def post(self, request: Request, *args: Any, **kwargs: Any) -> Response:
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
	throttle_scope = "token_refresh"

	@extend_schema(
		parameters=[
			OpenApiParameter(
				name="X-Refresh-Request",
				type=str,
				location=OpenApiParameter.HEADER,
				required=True,
				description="Must be set to 1 for refresh requests.",
			)
		],
		request=TokenRefreshRequestSerializer,
		responses={status.HTTP_200_OK: TokenAccessResponseSerializer},
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
	throttle_scope = "token_logout"

	@extend_schema(
		request=TokenRefreshRequestSerializer,
		responses={status.HTTP_200_OK: TokenLogoutResponseSerializer},
	)
	def post(self, request: Request) -> Response:
		raw_refresh_token = request.COOKIES.get(settings.JWT_REFRESH_COOKIE_NAME, "")
		if raw_refresh_token:
			revoke_refresh_family_for_token(
				raw_refresh_token,
				reason="logout",
			)
		response = Response({"status": "ok"}, status=status.HTTP_200_OK)
		_clear_refresh_cookie(response)
		return response


class ThrottledTokenVerifyView(TokenThrottleMixin, TokenVerifyView):
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
		# Account creation, ie. registration, needs to work for visitors without an account
		if self.request.method == "POST":
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

		user.set_password(new_password)
		user.save(update_fields=["password", "date_modified"])

		return Response({"status": "ok"})


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

		user.set_password(new_password)
		user.save(update_fields=["password", "date_modified"])

		# Clean up used code
		PasswordResetCode.objects.filter(user=user).delete()

		return Response({"status": "ok"})
