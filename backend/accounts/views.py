import logging

from django.conf import settings
from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.permissions import AllowAny, IsAdminUser, IsAuthenticated
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.serializers import BaseSerializer
from rest_framework.throttling import BaseThrottle, ScopedRateThrottle, UserRateThrottle
from rest_framework.views import APIView
from rest_framework.viewsets import ModelViewSet
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView, TokenVerifyView

from accounts.models import User
from accounts.serializers import (
	UserCreationSerializer,
	UserFullReadSerializer,
	UserMinimalReadSerializer,
)
from commons.permissions import IsRequestingThemselves, ReadOnly


class DevBootstrapTokenObtainPairSerializer(TokenObtainPairSerializer):
	def validate(self, attrs):
		self._ensure_dev_user(attrs)
		return super().validate(attrs)

	def _ensure_dev_user(self, attrs: dict) -> None:
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


class TokenThrottleMixin:
	"""Disables throttling in tests; applies UserRateThrottle + ScopedRateThrottle otherwise.

	Subclasses must set throttle_scope so ScopedRateThrottle picks up the right rate.
	"""

	throttle_scope: str

	def get_throttles(self) -> list[BaseThrottle]:
		if settings.TESTING:
			return []
		return [UserRateThrottle(), ScopedRateThrottle()]


class DevBootstrapTokenObtainPairView(TokenThrottleMixin, TokenObtainPairView):
	serializer_class = DevBootstrapTokenObtainPairSerializer
	throttle_scope = "login"


class ThrottledTokenRefreshView(TokenThrottleMixin, TokenRefreshView):
	throttle_scope = "token_refresh"


class ThrottledTokenVerifyView(TokenThrottleMixin, TokenVerifyView):
	throttle_scope = "token_verify"


class UserViewSet(ModelViewSet):
	permission_classes = [IsAuthenticated, (ReadOnly | IsRequestingThemselves | IsAdminUser)]
	queryset = User.objects.all()

	def get_throttles(self) -> list[BaseThrottle]:
		"""Apply stricter 'register' throttle on account creation."""
		if self.action == "create" and not settings.TESTING:
			self.throttle_scope = "register"
			return [*super().get_throttles(), ScopedRateThrottle()]
		return super().get_throttles()

	def get_serializer_class(self) -> type[BaseSerializer]:
		requester_pk = self.request.user.pk if not self.request.user.is_anonymous else None
		wanted_pk = self.kwargs.get("pk", None)

		match (self.request.method, requester_pk):
			case ("POST" | "PUT" | "PATCH", _):
				return UserCreationSerializer
			case ("GET", wanted_pk) if wanted_pk is not None:
				return UserFullReadSerializer
			case _:
				return UserMinimalReadSerializer

		# For mypy
		return UserMinimalReadSerializer

	def get_permissions(self):
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

	def post(self, request: Request) -> Response:
		from accounts.models.password_reset import PasswordResetCode
		from accounts.serializers import PasswordResetRequestSerializer
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

	def post(self, request: Request) -> Response:
		from accounts.models.password_reset import PasswordResetCode
		from accounts.serializers import PasswordResetConfirmSerializer

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
