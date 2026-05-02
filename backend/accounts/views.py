
from django.conf import settings
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.permissions import IsAdminUser, IsAuthenticated
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.serializers import BaseSerializer
from rest_framework.throttling import ScopedRateThrottle, UserRateThrottle
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

# Imported here rather than django.conf.settings so TESTING (a module-level
# variable, not a Django setting) is directly accessible.
from notif.settings import TESTING


class DevBootstrapTokenObtainPairSerializer(TokenObtainPairSerializer):
	def validate(self, attrs):
		self._ensure_dev_user(attrs)
		return super().validate(attrs)

	def _ensure_dev_user(self, attrs: dict) -> None:
		if not settings.DEV_BOOTSTRAP_LOGIN_ENABLED:
			return

		username = attrs.get(self.username_field)
		password = attrs.get('password')
		if (
			username != settings.DEV_BOOTSTRAP_USERNAME or
			password != settings.DEV_BOOTSTRAP_PASSWORD
		):
			return

		existing_user = User._base_manager.filter(username=username).first()
		if existing_user is not None:
			if existing_user.date_deleted is not None or not existing_user.is_active:
				existing_user.date_deleted = None
				existing_user.is_active = True
				existing_user.save(update_fields=['date_deleted', 'is_active', 'date_modified'])
			return

		User.objects.create_user(
			email=settings.DEV_BOOTSTRAP_EMAIL,
			username=settings.DEV_BOOTSTRAP_USERNAME,
			password=settings.DEV_BOOTSTRAP_PASSWORD,
			name=settings.DEV_BOOTSTRAP_NAME,
		)


class DevBootstrapTokenObtainPairView(TokenObtainPairView):
	serializer_class = DevBootstrapTokenObtainPairSerializer
	throttle_scope = 'login'

	def get_throttles(self):
		throttles = [UserRateThrottle()]
		if not TESTING:
			throttles.append(ScopedRateThrottle())
		return throttles


class ThrottledTokenRefreshView(TokenRefreshView):
	throttle_scope = 'token_refresh'

	def get_throttles(self):
		throttles = [UserRateThrottle()]
		if not TESTING:
			throttles.append(ScopedRateThrottle())
		return throttles


class ThrottledTokenVerifyView(TokenVerifyView):
	throttle_scope = 'token_verify'

	def get_throttles(self):
		throttles = [UserRateThrottle()]
		if not TESTING:
			throttles.append(ScopedRateThrottle())
		return throttles


class UserViewSet(ModelViewSet):
	permission_classes = [IsAuthenticated, (ReadOnly | IsRequestingThemselves | IsAdminUser)]
	queryset = User.objects.all()

	def get_throttles(self):
		"""Apply stricter 'register' throttle on account creation."""
		throttles = super().get_throttles()
		if self.action == 'create' and not TESTING:
			throttles.append(ScopedRateThrottle())
		return throttles

	def get_serializer_class(self) -> type[BaseSerializer]:
		requester_pk = self.request.user.pk if not self.request.user.is_anonymous else None
		wanted_pk = self.kwargs.get('pk', None)

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

	@action(detail=False, methods=['get', 'post'], permission_classes=[IsAuthenticated])
	def get_my_info(self, request: Request) -> Response:
		user = request.user
		assert isinstance(user, User)
		return Response(
			status=status.HTTP_200_OK,
			data=UserFullReadSerializer(user).data
		)
